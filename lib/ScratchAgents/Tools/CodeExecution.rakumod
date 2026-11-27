unit module ScratchAgents::Tools::CodeExecution;

use Cro::HTTP::Client;
use JSON::Fast;
use ScratchAgents::Tools::Base;
use ScratchAgents::Context;

#| Execute Python code in an E2B sandbox.
sub execute-python(ExecutionContext :$context!, Str :$code! --> Str) is export {
    die "No code execution environment available." unless $context.code-env.defined;
    my $sandbox = $context.code-env;

    # Call E2B REST API to run code
    my $client = Cro::HTTP::Client.new(
        headers => [
            Authorization => "Bearer { %*ENV<E2B_API_KEY> // '' }",
        ],
    );

    my %body = code => $code;
    my $resp = await $client.post(
        "https://api.e2b.dev/sandboxes/{$sandbox<sandbox-id>}/code",
        body => %body,
        content-type => 'application/json',
    );
    await $resp.body-text;
}

#| Execute a bash command in an E2B sandbox.
sub bash-tool(ExecutionContext :$context!, Str :$command! --> Str) is export {
    die "No code execution environment available." unless $context.code-env.defined;
    my $sandbox = $context.code-env;

    my $client = Cro::HTTP::Client.new(
        headers => [
            Authorization => "Bearer { %*ENV<E2B_API_KEY> // '' }",
        ],
    );

    my %body = command => $command;
    my $resp = await $client.post(
        "https://api.e2b.dev/sandboxes/{$sandbox<sandbox-id>}/commands",
        body => %body,
        content-type => 'application/json',
    );
    await $resp.body-text;
}

#| Upload a local file to the E2B sandbox.
sub upload-file(ExecutionContext :$context!, Str :$local-path!, Str :$sandbox-path = Str --> Str) is export {
    die "No code execution environment available" unless $context.code-env.defined;

    my $target = $sandbox-path // "/home/user/{ $local-path.IO.basename }";
    try {
        my $data = $local-path.IO.slurp(:bin);
        # Store file data in sandbox state for the sandbox to handle
        $context.code-env<files>{$target} = $data;
        return "File uploaded to $target";
        CATCH {
            default { return "Upload error: { .message }" }
        }
    }
}

=begin pod

=head1 NAME

ScratchAgents::Tools::CodeExecution - E2B sandbox code execution and file upload tools

=head1 SYNOPSIS

=begin code :lang<raku>
use ScratchAgents::Tools::Base;
use ScratchAgents::Tools::CodeExecution;

my @tools = tool(&execute-python), tool(&bash-tool), tool(&upload-file);
=end code

=head1 DESCRIPTION

Exports sandbox tools operating against C<$context.code-env> via the E2B REST API (authenticated with C<< $*ENV<E2B_API_KEY> >>):

=item C<< execute-python(ExecutionContext :$context!, Str :$code! --> Str) >> — Runs Python code in the active E2B sandbox.
=item C<< bash-tool(ExecutionContext :$context!, Str :$command! --> Str) >> — Runs a shell command in the active E2B sandbox.
=item C<< upload-file(ExecutionContext :$context!, Str :$local-path!, Str :$sandbox-path --> Str) >> — Reads a local file and stages it into the sandbox file map.

=end pod
