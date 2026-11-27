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

#| Send a sequence of JSON-RPC requests to a stdio MCP server and wait for the target response ID.
sub mcp-rpc-call(%connection, @requests, Int :$wait-id!, Num(Cool) :$timeout = 10e0 --> Hash) {
    my $proc = Proc::Async.new(
        %connection<command>,
        |(%connection<args> // []),
        :w,
    );

    my $done = Promise.new;
    my $vow  = $done.vow;
    my $raw  = '';

    $proc.stdout.lines.tap(-> $line {
        $raw ~= "$line\n";
        next unless $line.trim.starts-with('{');
        try {
            my %msg = from-json($line);
            if (%msg<id>:exists) && (%msg<id>.Int == $wait-id) {
                $vow.keep(%msg) unless $done.status ~~ Kept | Broken;
            }
            CATCH { default { } }
        }
    });
    $proc.stderr.tap(-> $ { });

    my $handle = $proc.start;

    for @requests -> %req {
        await $proc.say(to-json(%req, :!pretty));
    }

    await Promise.anyof($done, Promise.in($timeout));
    try { $proc.close-stdin }
    try { $proc.kill }
    try { await Promise.anyof($handle, Promise.in(1)) }

    return $done.status == Kept ?? $done.result !! { raw => $raw };
}

#| Create a FunctionTool that wraps an MCP tool.
sub create-mcp-tool(%mcp-tool, %connection --> FunctionTool) {
    my $tool-name = %mcp-tool<name>;
    my $tool-desc = %mcp-tool<description> // '';

    my &call-mcp = sub (*%kwargs) {
        my @reqs = (
            {
                jsonrpc => '2.0',
                id      => 1,
                method  => 'initialize',
                params  => {
                    protocolVersion => '2024-11-05',
                    capabilities    => {},
                    clientInfo      => { name => 'ScratchAgents-Raku', version => '0.1.0' },
                },
            },
            {
                jsonrpc => '2.0',
                id      => 2,
                method  => 'tools/call',
                params  => {
                    name      => $tool-name,
                    arguments => %kwargs,
                },
            },
        );

        my %resp = mcp-rpc-call(%connection, @reqs, :wait-id(2));
        return extract-text-content(%resp<result>) if %resp<result>:exists;
        return "MCP error: { to-json(%resp<error>, :!pretty) }" if %resp<error>:exists;
        %resp<raw> // '';
    };

    my %tool-definition = (
        type     => 'function',
        function => {
            name        => $tool-name,
            description => $tool-desc,
            parameters  => %mcp-tool<inputSchema> // { type => 'object', properties => {} },
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
    my @reqs = (
        {
            jsonrpc => '2.0',
            id      => 1,
            method  => 'initialize',
            params  => {
                protocolVersion => '2024-11-05',
                capabilities    => {},
                clientInfo      => { name => 'ScratchAgents-Raku', version => '0.1.0' },
            },
        },
        {
            jsonrpc => '2.0',
            id      => 2,
            method  => 'tools/list',
            params  => {},
        },
    );

    my %resp = mcp-rpc-call(%connection, @reqs, :wait-id(2));
    my @tools;
    if (%resp<result>:exists) && (%resp<result><tools>:exists) {
        for %resp<result><tools>.list -> %mcp-tool {
            @tools.push(create-mcp-tool(%mcp-tool, %connection));
        }
    }
    @tools;
}

#| Convert MCP tool definitions to OpenAI tool format.
sub mcp-tools-to-openai-format(@mcp-tools --> Array) is export {
    @mcp-tools.map({
        format-tool-definition(.<name>, .<description> // '', .<inputSchema> // {})
    }).Array;
}

=begin pod

=head1 NAME

ScratchAgents::Tools::Mcp - Model Context Protocol (MCP) stdio client adapter

=head1 SYNOPSIS

=begin code :lang<raku>
use ScratchAgents::Tools::Mcp;

my @mcp-tools = load-mcp-tools({
    command => $*EXECUTABLE.Str,
    args    => ['examples/mcp-demo-server.raku'],
});
=end code

=head1 DESCRIPTION

Connects to stdio JSON-RPC 2.0 MCP servers via C<Proc::Async> and converts discovered MCP tools into C<FunctionTool> instances compatible with C<ScratchAgents::Agent>:

=item C<< load-mcp-tools(%connection --> Array) >> — Performs C<initialize> and C<tools/list> over stdio and wraps every returned tool in a C<FunctionTool> that invokes C<tools/call>.
=item C<< mcp-tools-to-openai-format(@mcp-tools --> Array) >> — Converts raw MCP tool schemas into OpenAI tool definitions.

=end pod
