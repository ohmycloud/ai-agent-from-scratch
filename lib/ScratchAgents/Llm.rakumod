unit module ScratchAgents::Llm;

use Cro::HTTP::Client;
use JSON::Fast;
use ScratchAgents::Types;
use ScratchAgents::Tools::Base;

#| Request object for LLM calls.
class LlmRequest is export {
    has Str @.instructions is rw;
    has     @.contents     is rw;  # Array of ContentItem
    has     @.tools        is rw;  # Array of BaseTool
    has Str $.tool-choice  is rw = Str;
    has Str $.model-id     is rw = Str;

    method append-instructions(Str $text) {
        @!instructions.push($text);
    }
}

#| Response object from LLM calls.
class LlmResponse is export {
    has     @.content;          # Array of ContentItem
    has Str $.error-message = Str;
    has     %.usage-metadata;
}

#| Convert LlmRequest to API message format.
sub build-messages(LlmRequest $request --> Array) is export {
    my @messages;

    for $request.instructions -> $instruction {
        @messages.push({ role => 'system', content => $instruction });
    }

    for $request.contents -> $item {
        given $item {
            when Message {
                @messages.push(%( role => .role, content => .content ));
            }
            when ToolCall {
                my %tool-call-dict = (
                    id       => .tool-call-id,
                    type     => 'function',
                    function => %(
                        name      => .name,
                        arguments => to-json(.arguments, :!pretty),
                    ),
                );
                if @messages && @messages[*-1]<role> eq 'assistant' {
                    @messages[*-1]<tool_calls> //= [];
                    @messages[*-1]<tool_calls>.push(%tool-call-dict);
                } else {
                    @messages.push(%(
                        role       => 'assistant',
                        content    => Str,
                        tool_calls => [%tool-call-dict,],
                    ));
                }
            }
            when ToolResult {
                @messages.push(%(
                    role         => 'tool',
                    tool_call_id => .tool-call-id,
                    content      => .content.elems ?? ~.content[0] !! '',
                ));
            }
        }
    }

    @messages;
}

#| Client for LLM API calls using Cro::HTTP::Client.
class LlmClient is export {
    has Str  $.model    is required;
    has      %.config;
    has Str  $.api-key  = %*ENV<OPENAI_API_KEY>  // '';
    has Str  $.base-url = %*ENV<OPENAI_BASE_URL> // 'https://api.openai.com/v1';
    has Bool $!force-stream = False;

    method generate(LlmRequest $request --> LlmResponse) {
        try {
            my @messages = build-messages($request);
            my @tools = $request.tools.grep({ .tool-definition.defined }).map({ .tool-definition });

            my %body = (
                |%!config,
                model    => ($request.model-id || $!model),
                messages => @messages,
                stream   => (%!config<stream> // $!force-stream),
            );
            %body<tools>       = @tools if @tools;
            %body<tool_choice> = $request.tool-choice if $request.tool-choice;

            my $client = Cro::HTTP::Client.new(
                headers => [
                    Authorization => "Bearer $!api-key",
                ],
            );

            my $resp = await $client.post(
                "$!base-url/chat/completions",
                body         => %body,
                content-type => 'application/json',
            );
            my $raw-body = (await $resp.body-blob).decode('utf-8').trim;
            my Bool $is-sse = self!is-sse-body($raw-body);
            my %result   = self!decode-body($raw-body);

            if %result<error>:exists {
                my $err = %result<error> ~~ Associative
                    ?? (%result<error><message> // to-json(%result<error>, :!pretty))
                    !! ~%result<error>;
                return LlmResponse.new(error-message => $err);
            }

            my $parsed = self!parse-response(%result);

            # Some OpenAI-compatible gateways return an empty SSE chunk unless stream => True.
            if $is-sse && !$parsed.content.elems && !(%body<stream>) {
                $!force-stream = True;
                %body<stream> = True;
                my $retry-client = Cro::HTTP::Client.new(
                    headers => [
                        Authorization => "Bearer $!api-key",
                    ],
                );
                my $stream-resp = await $retry-client.post(
                    "$!base-url/chat/completions",
                    body         => %body,
                    content-type => 'application/json',
                );
                my $stream-body = (await $stream-resp.body-blob).decode('utf-8').trim;
                my %stream-res  = self!decode-body($stream-body);
                if %stream-res<error>:exists {
                    my $err = %stream-res<error> ~~ Associative
                        ?? (%stream-res<error><message> // to-json(%stream-res<error>, :!pretty))
                        !! ~%stream-res<error>;
                    return LlmResponse.new(error-message => $err);
                }
                return self!parse-response(%stream-res);
            }

            return $parsed;

            CATCH {
                when X::Cro::HTTP::Error {
                    my $err-body = '';
                    try { $err-body = await .response.body-text }
                    my $msg = $err-body ?? "{ .message }: $err-body" !! .message;
                    return LlmResponse.new(error-message => $msg);
                }
                default {
                    return LlmResponse.new(error-message => .message);
                }
            }
        }
    }

    #| Convenience method for one-shot prompts with optional structured output.
    method ask(Str $prompt, :$response-format = Nil --> Any) {
        my Bool $has-format = $response-format.defined
            || ($response-format !=== Any && $response-format !=== Nil && $response-format !=== Mu);

        my $instruction;
        my $schema;
        if $has-format {
            $schema = $response-format.^can('json-schema')
                ?? $response-format.json-schema
                !! $response-format;
            my $schema-text = to-json($schema, :!pretty);
            $instruction = "$prompt\n\nRespond ONLY with valid JSON matching this schema:\n$schema-text";
        } else {
            $instruction = $prompt;
        }

        my $request = LlmRequest.new(
            model-id     => $!model,
            instructions => [$instruction],
            contents     => [Message.new(role => 'user', content => 'Please respond.')],
        );
        my $response = self.generate($request);
        if $response.error-message {
            die "LLM request failed: { $response.error-message }";
        }

        my $text = '';
        for $response.content -> $item {
            if $item ~~ Message {
                $text = $item.content;
                last;
            }
        }

        return $text unless $has-format;

        my $cleaned = $text.trim;
        if $cleaned.starts-with('```') {
            $cleaned = $cleaned.lines[1..*].join("\n") if $cleaned.contains("\n");
            $cleaned = $cleaned.subst(/ '```' $ /, '');
            $cleaned = $cleaned.subst(/ ^ 'json' \s* /, '');
        }
        my $parsed = from-json($cleaned.trim);
        if $response-format.^can('from-hash') && $parsed ~~ Associative {
            return $response-format.from-hash($parsed);
        }
        $parsed;
    }

    method !is-sse-body(Str $raw-body --> Bool) {
        $raw-body.starts-with('data:') || $raw-body.starts-with('event:') || $raw-body.starts-with(':');
    }

    method !decode-body(Str $raw-body --> Hash) {
        if self!is-sse-body($raw-body) {
            return self!parse-sse-body($raw-body);
        }
        from-json($raw-body);
    }

    method !parse-sse-body(Str $raw-body --> Hash) {
        my Str $content = '';
        my %tool-calls-by-idx;
        my %usage;

        for $raw-body.lines -> $line {
            my $trimmed = $line.trim;
            next unless $trimmed.starts-with('data:');
            my $payload = $trimmed.substr(5).trim;
            last if $payload eq '[DONE]';
            next unless $payload.chars;

            my %chunk = from-json($payload);
            %usage = %chunk<usage> if %chunk<usage> ~~ Associative;

            my $choices = %chunk<choices>;
            next unless $choices ~~ Positional && $choices.elems;
            my %choice = $choices[0];
            my %delta  = (%choice<delta> // %choice<message> // {}).Hash;

            if %delta<content>.defined {
                $content ~= ~%delta<content>;
            }

            if %delta<tool_calls> ~~ Positional {
                for %delta<tool_calls>.list -> %tc {
                    my $idx = ~(%tc<index> // 0);
                    %tool-calls-by-idx{$idx} //= {
                        id       => '',
                        type     => 'function',
                        function => { name => '', arguments => '' },
                    };
                    %tool-calls-by-idx{$idx}<id> = ~%tc<id> if %tc<id>.defined && %tc<id>.chars;
                    if %tc<function> ~~ Associative {
                        %tool-calls-by-idx{$idx}<function><name>      ~= ~%tc<function><name>      if %tc<function><name>.defined;
                        %tool-calls-by-idx{$idx}<function><arguments> ~= ~%tc<function><arguments> if %tc<function><arguments>.defined;
                    }
                }
            }
        }

        my %message = (role => 'assistant');
        %message<content> = $content if $content.chars;
        if %tool-calls-by-idx.elems {
            %message<tool_calls> = %tool-calls-by-idx.keys.sort(*.Int).map({ %tool-calls-by-idx{$_} }).Array;
        }

        {
            choices => [{ message => %message },],
            usage   => %usage,
        };
    }

    method !parse-response(%response --> LlmResponse) {
        my %choice = %response<choices>[0];
        my @content-items;

        if %choice<message><content> {
            @content-items.push(Message.new(
                role    => 'assistant',
                content => %choice<message><content>,
            ));
        }

        if %choice<message><tool_calls> {
            for %choice<message><tool_calls>.list -> %tc {
                my $raw-args = %tc<function><arguments>;
                my %args = $raw-args ~~ Associative
                    ?? $raw-args.Hash
                    !! ($raw-args.defined && ~$raw-args.trim.chars ?? from-json(~$raw-args) !! {});
                @content-items.push(ToolCall.new(
                    tool-call-id => %tc<id>,
                    name         => %tc<function><name>,
                    arguments    => %args,
                ));
            }
        }

        LlmResponse.new(
            content        => @content-items,
            usage-metadata => {
                input-tokens  => %response<usage><prompt_tokens>     // 0,
                output-tokens => %response<usage><completion_tokens> // 0,
            },
        );
    }
}
