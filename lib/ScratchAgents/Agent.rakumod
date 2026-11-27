unit module ScratchAgents::Agent;

use Cro::HTTP::Client;
use JSON::Fast;
use ScratchAgents::Context;
use ScratchAgents::Llm;
use ScratchAgents::Skills;
use ScratchAgents::Tools::Base;
use ScratchAgents::Tools::CodeExecution;
use ScratchAgents::Tools::Helpers;
use ScratchAgents::Tools::MemoryTool;
use ScratchAgents::Transfer;
use ScratchAgents::Types;

#| Tool-calling agent with a ReAct loop.
#| Supports structured output, callbacks, sessions, memory,
#| code execution, skills, and multi-agent patterns.
class Agent is export {
    has      $.model                      is rw = Nil;
    has      @.tools                      is rw;
    has Str  $.instructions               is rw = '';
    has Int  $.max-steps                  is rw = 10;
    has Str  $.name                       is rw = 'agent';
    has Str  $.description                is rw = '';
    # CH04 structured output
    has      $.output-type                is rw = Nil;
    has Str  $.output-tool-name           is rw = Str;
    # CH05 callbacks
    has      @.before-tool-callbacks      is rw;
    has      @.after-tool-callbacks       is rw;
    # CH06 session & memory
    has      $.session-manager            is rw = Nil;
    has      $.memory-manager             is rw = Nil;
    has      @.before-llm-callbacks       is rw;
    # CH08 code execution & skills
    has Str  $.code-execution             is rw = Str;
    has Str  $.skills-path                is rw = Str;
    has      &.sandbox-factory            is rw = Nil;
    # CH09 multi-agent
    has      @.sub-agents                 is rw;
    has Bool $.disallow-transfer-to-peers is rw = False;
    has      $.parent                     is rw = Nil;
    has      @!sandbox-tools;

    multi method new($model, *%args) {
        self.bless(:$model, |%args);
    }

    multi method new(*%args) {
        self.bless(|%args);
    }

    submethod TWEAK() {
        @!tools = self!setup-tools(@!tools);
        self!validate-and-set-sub-agents() if @!sub-agents;
    }

    #| Execute the agent loop.
    method run(
        $pos-user-input = Nil,
        :$user-input is copy = Nil,
        ExecutionContext :$context is copy = ExecutionContext,
        Str  :$session-id = Str,
        :@tool-confirmations,
        Bool :$verbose = False,
        --> AgentResult
    ) {
        $user-input //= $pos-user-input;

        my $session = Nil;
        if $session-id.defined && $session-id.chars && $!session-manager.defined {
            $session = $!session-manager.get-or-create($session-id);
        }

        if !$context.defined {
            $context = ExecutionContext.new(
                session         => $session,
                session-manager => $!session-manager,
                memory-manager  => $!memory-manager,
            );
            if $session.defined {
                $context.events.append($session.events);
                $context.state = deep-copy($session.state);
            }
        } elsif !$context.memory-manager.defined {
            $context.memory-manager = $!memory-manager;
        }

        if @tool-confirmations {
            self!process-confirmations($context, @tool-confirmations);
        }

        if $user-input.defined && ~$user-input ne '' {
            my $user-event = Event.new(
                execution-id => $context.execution-id,
                author       => 'user',
                content      => [Message.new(role => 'user', content => ~$user-input)],
            );
            $context.add-event($user-event);
        }

        if ($!code-execution // '') eq 'e2b' && !$context.code-env.defined {
            self!setup-code-env($context);
        }

        LEAVE {
            if $context.defined && $context.code-env.defined {
                my $sandbox = $context.code-env;
                $context.code-env = Nil;
                self!kill-sandbox($sandbox);
            }
        }

        while !$context.final-result.defined && $context.current-step < $!max-steps {
            my $step-res = self.step($context, :$verbose);

            if $step-res.defined && $step-res.status eq 'pending_confirmation' {
                if $session.defined && $!session-manager.defined {
                    $session.events = $context.events.Array;
                    $session.state  = deep-copy($context.state);
                    $!session-manager.save($session);
                }
                return $step-res;
            }

            if $context.events.elems {
                my $last-event = $context.events[*-1];
                if self!is-final-response($last-event) {
                    $context.final-result = self!extract-final-result($last-event);
                }
            }

            if $context.transfer-to.defined {
                my $target-name = $context.transfer-to;
                $context.transfer-to = Str;
                my $target = self!find-agent($target-name);
                if $target.defined {
                    return $target.run(:$context, :$verbose);
                }
            }
        }

        if $!memory-manager.defined {
            try {
                $!memory-manager.save($context);
                CATCH {
                    default { note "Failed to save memory: { .message }" }
                }
            }
        }

        if $session.defined && $!session-manager.defined {
            $session.events = $context.events.Array;
            $session.state  = deep-copy($context.state);
            $!session-manager.save($session);
        }

        AgentResult.new(output => $context.final-result, :$context);
    }

    #| Perform one think-act cycle.
    method step(ExecutionContext $context, Bool :$verbose = False --> AgentResult) {
        my $llm-request  = self!prepare-llm-request($context);
        my $llm-response = LlmResponse;

        for @!before-llm-callbacks -> $cb {
            my $cb-res = $cb($context, $llm-request);
            $cb-res = await $cb-res if $cb-res ~~ Promise;
            if $cb-res ~~ LlmResponse {
                $llm-response = $cb-res;
                last;
            }
        }

        unless $llm-response.defined {
            $llm-response = self.think($llm-request);
        }

        if $llm-response.error-message {
            die "LLM request failed: { $llm-response.error-message }";
        }

        self!log-response($llm-response) if $verbose;

        my $response-event = Event.new(
            execution-id => $context.execution-id,
            author       => $!name,
            content      => $llm-response.content,
        );
        $context.add-event($response-event);

        my @tool-calls = $llm-response.content.grep({ $_ ~~ ToolCall });
        if @tool-calls {
            my $result = self.act($context, @tool-calls);
            if $result.defined && $result.status eq 'pending_confirmation' {
                return $result;
            }
        }

        $context.increment-step();
        AgentResult;
    }

    #| Call the LLM to decide the next action.
    method think(LlmRequest $llm-request --> LlmResponse) {
        die "Agent '$!name' has no model configured" unless $!model.defined;
        my $res = $!model.generate($llm-request);
        $res ~~ Promise ?? await($res) !! $res;
    }

    #| Execute the tools requested by the LLM.
    method act(ExecutionContext $context, @tool-calls --> AgentResult) {
        my %tools-dict = @!tools.map({ .name => $_ });
        my @results;
        my @pending;

        for @tool-calls -> $tc {
            unless %tools-dict{$tc.name}:exists {
                @results.push(ToolResult.new(
                    tool-call-id => $tc.tool-call-id,
                    name         => $tc.name,
                    status       => 'error',
                    content      => ["Tool '{ $tc.name }' not found"],
                ));
                next;
            }

            my $tool-obj = %tools-dict{$tc.name};

            if $tool-obj.requires-confirmation {
                my $msg = $tool-obj.get-confirmation-message($tc.arguments);
                @pending.push(PendingToolCall.new(
                    tool-call            => $tc,
                    confirmation-message => $msg,
                ));
                next;
            }

            my Bool $skip = False;
            for @!before-tool-callbacks -> $cb {
                my $cb-res = $cb($context, $tc);
                $cb-res = await $cb-res if $cb-res ~~ Promise;
                if $cb-res.defined {
                    @results.push(ToolResult.new(
                        tool-call-id => $tc.tool-call-id,
                        name         => $tc.name,
                        status       => 'success',
                        content      => [$cb-res],
                    ));
                    $skip = True;
                    last;
                }
            }
            next if $skip;

            my $tool-result;
            try {
                my $output = $tool-obj($context, |$tc.arguments);
                $output = await $output if $output ~~ Promise;
                $tool-result = ToolResult.new(
                    tool-call-id => $tc.tool-call-id,
                    name         => $tc.name,
                    status       => 'success',
                    content      => [$output],
                );
                CATCH {
                    default {
                        $tool-result = ToolResult.new(
                            tool-call-id => $tc.tool-call-id,
                            name         => $tc.name,
                            status       => 'error',
                            content      => [.message],
                        );
                    }
                }
            }

            for @!after-tool-callbacks -> $cb {
                my $cb-res = $cb($context, $tool-result);
                $cb-res = await $cb-res if $cb-res ~~ Promise;
                $tool-result = $cb-res if $cb-res.defined;
            }

            @results.push($tool-result);
        }

        if @pending {
            $context.state<pending_tool_calls> = @pending.map({ .to-hash }).Array;
            if @results {
                $context.add-event(Event.new(
                    execution-id => $context.execution-id,
                    author       => $!name,
                    content      => @results,
                ));
            }
            return AgentResult.new(
                output             => Nil,
                :$context,
                status             => 'pending_confirmation',
                pending-tool-calls => @pending,
            );
        }

        if @results {
            $context.add-event(Event.new(
                execution-id => $context.execution-id,
                author       => $!name,
                content      => @results,
            ));
        }

        AgentResult;
    }

    method !prepare-llm-request(ExecutionContext $context --> LlmRequest) {
        my @flat-contents;
        for $context.events -> $event {
            @flat-contents.append($event.content);
        }

        my Str @instructions;
        @instructions.push($!instructions) if $!instructions.chars;

        my $sandbox-prompt = self!get-sandbox-tools-prompt();
        @instructions.push($sandbox-prompt) if $sandbox-prompt.chars;

        if $!skills-path.defined && $!skills-path.chars {
            try {
                my @skills = discover-skills($!skills-path);
                my $skills-prompt = generate-skills-prompt(@skills);
                @instructions.push($skills-prompt) if $skills-prompt.chars;
                CATCH { default { } }
            }
        }

        my @llm-tools = @!tools.grep({ .tool-definition.defined });

        my Str $tool-choice = Str;
        if $!output-tool-name.defined {
            $tool-choice = 'required';
        } elsif @llm-tools {
            $tool-choice = 'auto';
        }

        my $model-id = ($!model.defined && $!model.^can('model')) ?? ($!model.model // '') !! '';
        my $request = LlmRequest.new(
            :$model-id,
            :@instructions,
            contents    => @flat-contents,
            tools       => @llm-tools,
            :$tool-choice,
        );

        for @!tools -> $tool-obj {
            $tool-obj.process-llm-request($context, $request);
        }

        $request;
    }

    method !is-final-response(Event $event --> Bool) {
        if $!output-tool-name.defined {
            for $event.content -> $item {
                if ($item ~~ ToolResult)
                    && ($item.name eq $!output-tool-name)
                    && ($item.status eq 'success')
                {
                    return True;
                }
            }
            return False;
        }

        my $has-calls   = so $event.content.first({ $_ ~~ ToolCall });
        my $has-results = so $event.content.first({ $_ ~~ ToolResult });
        !$has-calls && !$has-results;
    }

    method !extract-final-result(Event $event) {
        if $!output-tool-name.defined {
            for $event.content -> $item {
                if ($item ~~ ToolResult)
                    && ($item.name eq $!output-tool-name)
                    && ($item.status eq 'success')
                    && $item.content.elems
                {
                    return $item.content[0];
                }
            }
        }

        for $event.content -> $item {
            if ($item ~~ Message) && ($item.role eq 'assistant') {
                return $item.content;
            }
        }
        Nil;
    }

    method !setup-tools(@raw-tools --> Array) {
        my @tools = @raw-tools.map({
            $_ ~~ BaseTool ?? $_ !! FunctionTool.new(func => $_)
        }).Array;

        if $!output-type !=== Any && $!output-type !=== Nil {
            my %schema = $!output-type.^can('json-schema')
                ?? deep-copy($!output-type.json-schema)
                !! deep-copy($!output-type);
            %schema<title>:delete;
            %schema<$defs>:delete;

            my %tool-def = format-tool-definition(
                'final_answer',
                'Return the final structured answer matching the required schema.',
                {
                    type       => 'object',
                    properties => { output => %schema },
                    required   => ['output'],
                },
            );

            my $captured-type = $!output-type;
            my sub parse-output(:$output!) {
                if ($output ~~ Associative) && $captured-type.^can('from-hash') {
                    return $captured-type.from-hash($output);
                }
                $output;
            }

            @tools.push(FunctionTool.new(
                func            => &parse-output,
                name            => 'final_answer',
                description     => 'Return the final structured answer matching the required schema.',
                tool-definition => %tool-def,
            ));
            $!output-tool-name = 'final_answer';
        }

        my @invalid-sandbox;
        for @tools -> $t {
            next unless ($t ~~ FunctionTool) && $t.sandbox-executable;
            if ($!code-execution // '') ne 'e2b' {
                @invalid-sandbox.push($t.name);
                next;
            }
            @!sandbox-tools.push($t);
        }

        if @invalid-sandbox {
            die "Tools { @invalid-sandbox.join(', ') } are marked as sandbox_executable "
                ~ "but code_execution is not enabled.";
        }

        if ($!code-execution // '') eq 'e2b' {
            @tools.push(FunctionTool.new(func => &execute-python));
        }

        if @!sub-agents {
            @tools.push(create-transfer-tool(@!sub-agents));
        }

        if $!memory-manager.defined {
            @tools.push(MemoryTool.new);
        }

        @tools;
    }

    method !setup-code-env(ExecutionContext $context) {
        try {
            my $sandbox;
            if &!sandbox-factory.defined {
                $sandbox = &!sandbox-factory();
            } else {
                my $api-key = %*ENV<E2B_API_KEY> // die "E2B_API_KEY not set";
                my $client  = Cro::HTTP::Client.new(
                    headers => [
                        Authorization => "Bearer $api-key",
                    ],
                );
                my $resp = await $client.post(
                    'https://api.e2b.dev/sandboxes',
                    body         => { timeout => 300 },
                    content-type => 'application/json',
                );
                my %info = from-json(await $resp.body-text);
                $sandbox = {
                    sandbox-id => (%info<sandboxID> // %info<sandboxId> // ''),
                    files      => {},
                };
            }

            $context.code-env = $sandbox;
            self!register-sandbox-tools($sandbox) if @!sandbox-tools;

            if $!skills-path.defined && $!skills-path.chars {
                my @skills = discover-skills($!skills-path);
                for @skills -> $skill {
                    self!upload-skill-dir($sandbox, $skill);
                }
            }

            CATCH {
                default {
                    if $context.code-env.defined {
                        my $sb = $context.code-env;
                        $context.code-env = Nil;
                        self!kill-sandbox($sb);
                    }
                    die "Failed to set up code execution environment: { .message }";
                }
            }
        }
    }

    method !upload-skill-dir($sandbox, SkillInfo $skill) {
        my @stack = ($skill.path);
        while @stack {
            my $dir = @stack.pop;
            for $dir.dir -> $entry {
                if $entry.d {
                    @stack.push($entry);
                } elsif $entry.f {
                    my $rel = $entry.relative($skill.path).subst('\\', '/', :g);
                    my $target = "/home/user/skills/{ $skill.name }/$rel";
                    my $bytes  = $entry.slurp(:bin);
                    if $sandbox.^can('files') && $sandbox.files.defined {
                        $sandbox.files.write($target, $bytes);
                    } elsif $sandbox ~~ Associative {
                        $sandbox<files>{$target} = $bytes;
                    }
                }
            }
        }
    }

    method !kill-sandbox($sandbox) {
        try {
            if $sandbox.^can('kill') {
                $sandbox.kill();
            } elsif ($sandbox ~~ Associative) && $sandbox<sandbox-id> && %*ENV<E2B_API_KEY> {
                my $client = Cro::HTTP::Client.new(
                    headers => [ Authorization => "Bearer { %*ENV<E2B_API_KEY> }" ],
                );
                await $client.delete("https://api.e2b.dev/sandboxes/{ $sandbox<sandbox-id> }");
            }
            CATCH { default { } }
        }
    }

    method !register-sandbox-tools($sandbox) {
        my @sources = @!sandbox-tools.map({ .get-source-code });
        my $combined = @sources.join("\n\n");
        if $sandbox.^can('run-code') {
            my $res = $sandbox.run-code($combined);
            die "Failed to register sandbox tools: { $res.error }" if $res.^can('error') && $res.error;
        }
    }

    method !get-sandbox-tools-prompt(--> Str) {
        return '' unless @!sandbox-tools;
        my @defs = @!sandbox-tools.map({ .tool-definition });
        my $json = to-json(@defs, :pretty);
        "\n\n## Sandbox-Executable Tools\n"
        ~ "The following functions are pre-registered in the sandbox "
        ~ "and can be called directly in your Python code:\n"
        ~ $json;
    }

    method !get-transfer-targets(--> Array) {
        my @targets;
        @targets.append(@!sub-agents);
        if $!parent.defined {
            @targets.push($!parent);
            unless $!disallow-transfer-to-peers {
                for $!parent.sub-agents -> $sibling {
                    @targets.push($sibling) if $sibling.name ne $!name;
                }
            }
        }
        @targets;
    }

    method !find-agent(Str $name) {
        my $root = self;
        while $root.parent.defined {
            $root = $root.parent;
        }
        $root.find-in-subtree($name);
    }

    method find-in-subtree(Str $name) {
        return self if $!name eq $name;
        for @!sub-agents -> $sub {
            my $found = $sub.find-in-subtree($name);
            return $found if $found.defined;
        }
        Nil;
    }

    method !validate-and-set-sub-agents() {
        my %seen;
        for @!sub-agents -> $sub {
            die "Duplicate sub-agent name: '{ $sub.name }'" if %seen{$sub.name}:exists;
            %seen{$sub.name} = True;
            if $sub.parent.defined {
                die "Agent '{ $sub.name }' already has parent '{ $sub.parent.name }'";
            }
            $sub.parent = self;
        }
    }

    method !process-confirmations(ExecutionContext $context, @confirmations) {
        my $raw-pending = $context.state<pending_tool_calls>:delete // [];
        my @pending = $raw-pending.map({
            $_ ~~ PendingToolCall ?? $_ !! PendingToolCall.from-hash($_)
        });

        my %tools-dict = @!tools.map({ .name => $_ });
        my @results;

        for @pending -> $pending-call {
            my $tc = $pending-call.tool-call;
            my $confirmation = @confirmations.first({ .tool-call-id eq $tc.tool-call-id });

            if $confirmation.defined && $confirmation.approved {
                my %args = $confirmation.modified-arguments.elems
                    ?? $confirmation.modified-arguments
                    !! $tc.arguments;
                if %tools-dict{$tc.name}:exists {
                    my $tool-obj = %tools-dict{$tc.name};
                    try {
                        my $output = $tool-obj($context, |%args);
                        $output = await $output if $output ~~ Promise;
                        @results.push(ToolResult.new(
                            tool-call-id => $tc.tool-call-id,
                            name         => $tc.name,
                            status       => 'success',
                            content      => [$output],
                        ));
                        CATCH {
                            default {
                                @results.push(ToolResult.new(
                                    tool-call-id => $tc.tool-call-id,
                                    name         => $tc.name,
                                    status       => 'error',
                                    content      => [.message],
                                ));
                            }
                        }
                    }
                }
            } else {
                @results.push(ToolResult.new(
                    tool-call-id => $tc.tool-call-id,
                    name         => $tc.name,
                    status       => 'error',
                    content      => ['User denied the tool execution.'],
                ));
            }
        }

        if @results {
            $context.add-event(Event.new(
                execution-id => $context.execution-id,
                author       => $!name,
                content      => @results,
            ));
        }
    }

    method !log-response(LlmResponse $response) {
        for $response.content -> $item {
            given $item {
                when Message  { note "[{ $!name }] { .content }" }
                when ToolCall { note "[{ $!name }] Tool call: { .name }({ .arguments })" }
            }
        }
    }
}
