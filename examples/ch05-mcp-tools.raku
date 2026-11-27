use v6.d;
use lib 'lib';
use Env::Dotenv;
use JSON::Fast;
use ScratchAgents;
use ScratchAgents::Tools::Mcp;

# CH05: Using MCP (Model Context Protocol) tools in ScratchAgents.
#
# 1) Connects to the bundled pure-Raku stdio MCP server (examples/mcp-demo-server.raku)
#    (You can swap %connection for any external MCP server, e.g. `npx -y @modelcontextprotocol/server-filesystem .`)
# 2) Discovers tools via `load-mcp-tools`
# 3) Invokes discovered MCP tools directly
# 4) Runs an Agent with the MCP tools (pass `--live` to use your real LLM API from .env)

my $server-script = $*PROGRAM.parent.child('mcp-demo-server.raku').Str;
my %connection = (
    command => $*EXECUTABLE.Str,
    args    => [$server-script],
);

say "=== 1. Loading tools from MCP server ===";
my @mcp-tools = load-mcp-tools(%connection);
say "Discovered { @mcp-tools.elems } MCP tool(s):";
for @mcp-tools -> $t {
    say "  - { $t.name }: { $t.description }";
}

say "\n=== 2. Direct MCP tool invocation ===";
my $ctx = ExecutionContext.new;
my $wc  = @mcp-tools.first({ .name eq 'word_count' });
my $rev = @mcp-tools.first({ .name eq 'reverse_text' });

say "word_count('Raku MCP tools work') => " ~ $wc($ctx, text => 'Raku MCP tools work');
say "reverse_text('Raku')              => " ~ $rev($ctx, text => 'Raku');

say "\n=== 3. Running Agent with MCP tools ===";
my $use-live = so @*ARGS.grep('--live');

if $use-live {
    my $agent = Agent.new(
        model        => LlmClient.new(model => %*ENV<OPENAI_MODEL> // 'gpt-5.5'),
        tools        => @mcp-tools,
        instructions => 'Use the available MCP tools to answer the user.',
    );
    my $res = $agent.run("Count the words in 'Build an AI Agent from Scratch in Raku' and also reverse the word 'Raku'.", :verbose);
    say "\nLive Agent Answer:\n{ $res.output }";
} else {
    # Offline mock model demonstrating the full Agent -> MCP ToolCall -> ToolResult loop
    class McpDemoModel {
        has Str $.model = 'mock-mcp';
        has Int $!step  = 0;

        method generate(LlmRequest $req --> LlmResponse) {
            $!step++;
            if $!step == 1 {
                return LlmResponse.new(content => [
                    ToolCall.new(
                        tool-call-id => 'mcp_1',
                        name         => 'word_count',
                        arguments    => { text => 'Build an AI Agent from Scratch in Raku' },
                    ),
                    ToolCall.new(
                        tool-call-id => 'mcp_2',
                        name         => 'reverse_text',
                        arguments    => { text => 'Raku' },
                    ),
                ]);
            }
            my @results = $req.contents.grep({ $_ ~~ ToolResult }).map({ "{ .name }: { .content[0] }" });
            LlmResponse.new(content => [
                Message.new(role => 'assistant', content => "MCP results -> " ~ @results.join(' | ')),
            ]);
        }
    }

    my $agent = Agent.new(
        model => McpDemoModel.new,
        tools => @mcp-tools,
    );
    my $res = $agent.run('Analyze text with MCP tools', :verbose);
    say "\nAgent Answer:\n{ $res.output }";
    say "\nTip: run `raku examples/ch05-mcp-tools.raku --live` to test with your configured LLM API.";
}
