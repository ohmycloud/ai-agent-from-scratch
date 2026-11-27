unit module ScratchAgents::Tools::Mcp;

use JSON::Fast;
use ScratchAgents::Tools::Base;
use ScratchAgents::Tools::Helpers;

#| Extract plain text from an MCP CallToolResult.
sub extract-text-content($result --> Str) {
    my @parts;
    if ($result ~~ Associative) && ($result<content>:exists) {
        for $result<content>.list -> $item {
            @parts.push($item<text>) if $item<text>:exists;
        }
    }
    @parts.join("\n");
}

#| Create a FunctionTool that wraps an MCP tool.
sub create-mcp-tool(%mcp-tool, %connection --> FunctionTool) {
    my $tool-name = %mcp-tool<name>;
    my $tool-desc = %mcp-tool<description> // '';

    my &call-mcp = sub (*%kwargs) {
        # Launch MCP server as subprocess, send JSON-RPC request
        my $proc = Proc::Async.new(
            %connection<command>,
            |(%connection<args> // []),
        );

        my $stdout = '';
        $proc.stdout.tap({ $stdout ~= $_ });

        my $handle = $proc.start;

        # Send JSON-RPC call_tool request
        my %request = (
            jsonrpc => '2.0',
            id      => 1,
            method  => 'tools/call',
            params  => {
                name      => $tool-name,
                arguments => %kwargs,
            },
        );

        await $proc.say(to-json(%request, :!pretty));
        sleep 2;  # wait for response
        $proc.kill;

        try {
            my %resp = from-json($stdout.lines.tail // '{}');
            return extract-text-content(%resp<result> // {});
            CATCH { default { return $stdout } }
        }
    };

    my %tool-definition = (
        type     => 'function',
        function => {
            name        => $tool-name,
            description => $tool-desc,
            parameters  => %mcp-tool<inputSchema> // {},
        },
    );

    FunctionTool.new(
        func            => &call-mcp,
        name            => $tool-name,
        description     => $tool-desc,
        tool-definition => %tool-definition,
    );
}

#| Load tools from an MCP server and convert to FunctionTools.
sub load-mcp-tools(%connection --> Array) is export {
    my @tools;

    # Launch MCP server and list tools
    my $proc = Proc::Async.new(
        %connection<command>,
        |(%connection<args> // []),
    );

    my $stdout = '';
    $proc.stdout.tap({ $stdout ~= $_ });

    my $handle = $proc.start;

    # Send initialize request
    my %init-req = jsonrpc => '2.0', id => 1, method => 'initialize', params => {};
    await $proc.say(to-json(%init-req, :!pretty));
    sleep 1;

    # Send list_tools request
    my %list-req = jsonrpc => '2.0', id => 2, method => 'tools/list', params => {};
    await $proc.say(to-json(%list-req, :!pretty));
    sleep 1;

    $proc.kill;

    try {
        for $stdout.lines -> $line {
            my %resp = from-json($line);
            if %resp<result><tools>:exists {
                for %resp<result><tools>.list -> %mcp-tool {
                    @tools.push(create-mcp-tool(%mcp-tool, %connection));
                }
            }
        }
        CATCH { default { } }
    }

    @tools;
}

#| Convert MCP tool definitions to OpenAI tool format.
sub mcp-tools-to-openai-format(@mcp-tools --> Array) is export {
    @mcp-tools.map({
        format-tool-definition(.<name>, .<description> // '', .<inputSchema> // {})
    }).Array;
}
