use v6.d;
use JSON::Fast;

# Minimal stdio MCP (Model Context Protocol) JSON-RPC 2.0 server written in Raku.
# Launched automatically by examples/ch05-mcp-tools.raku via ScratchAgents::Tools::Mcp.

my @TOOLS = (
    {
        name        => 'word_count',
        description => 'Count the number of words and characters in the given text.',
        inputSchema => {
            type       => 'object',
            properties => {
                text => { type => 'string', description => 'Text to analyze' },
            },
            required => ['text'],
        },
    },
    {
        name        => 'reverse_text',
        description => 'Reverse the characters of the given string.',
        inputSchema => {
            type       => 'object',
            properties => {
                text => { type => 'string', description => 'Text to reverse' },
            },
            required => ['text'],
        },
    },
);

$*OUT.out-buffer = False;

for $*IN.lines -> $line {
    next unless $line.trim.chars;
    my %req = from-json($line);
    my $id  = %req<id>;

    my %result;
    given %req<method> // '' {
        when 'initialize' {
            %result = (
                protocolVersion => '2024-11-05',
                capabilities    => { tools => {} },
                serverInfo      => { name => 'raku-demo-mcp', version => '0.1.0' },
            );
        }
        when 'tools/list' {
            %result = (tools => @TOOLS);
        }
        when 'tools/call' {
            my $name = %req<params><name> // '';
            my %args = %req<params><arguments> // {};
            my $text = ~(%args<text> // '');

            my $out = do given $name {
                when 'word_count'   { "words={ $text.words.elems }, chars={ $text.chars }" }
                when 'reverse_text' { $text.flip }
                default             { "Unknown tool: $name" }
            };
            %result = (content => [{ type => 'text', text => $out },]);
        }
        default {
            next unless $id.defined;
            say to-json({ jsonrpc => '2.0', id => $id, error => { code => -32601, message => "Method not found" } }, :!pretty);
            next;
        }
    }

    say to-json({ jsonrpc => '2.0', id => $id, result => %result }, :!pretty) if $id.defined;
}
