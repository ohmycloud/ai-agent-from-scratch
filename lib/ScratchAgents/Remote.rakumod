unit module ScratchAgents::Remote;

use Cro::HTTP::Client;
use JSON::Fast;
use ScratchAgents::Context;

#| Client for interacting with remote agents via the A2A protocol.
class RemoteAgent is export {
    has Str $.base-url    is required;
    has Str $.name        is rw = '';
    has Str $.description is rw = '';

    submethod TWEAK() {
        $!base-url = $!base-url.subst(/ '/' + $ /, '');
        self!load-agent-info();
    }

    method !load-agent-info() {
        try {
            my $client = Cro::HTTP::Client.new;
            my $resp   = await $client.get("$!base-url/.well-known/agent.json");
            if $resp.status == 200 {
                my %info = from-json(await $resp.body-text);
                $!name        = %info<name> // 'remote_agent';
                $!description = %info<description> // '';
            }
            CATCH {
                default {
                    $!name = 'remote_agent';
                }
            }
        }
    }

    #| Send a request to the remote agent.
    method run(
        Str              $user-input,
        ExecutionContext :$context,
        Bool             :$verbose = False,
        --> AgentResult
    ) {
        my $ctx = $context // ExecutionContext.new;

        my $client = Cro::HTTP::Client.new;

        my %body = (
            jsonrpc => '2.0',
            method  => 'tasks/send',
            params  => {
                message => {
                    role  => 'user',
                    parts => [{ type => 'text', text => $user-input },],
                },
            },
        );

        my $resp = await $client.post(
            "$!base-url/tasks/send",
            body         => %body,
            content-type => 'application/json',
        );
        my %result = from-json(await $resp.body-text);
        my $output = '';

        if %result<result>:exists {
            my %task-result = %result<result>;
            if %task-result<artifacts>:exists {
                my @parts;
                for %task-result<artifacts>.list -> %artifact {
                    for (%artifact<parts> // []).list -> %part {
                        @parts.push(%part<text>) if (%part<type> // '') eq 'text';
                    }
                }
                $output = @parts.join("\n");
            }
        }

        AgentResult.new(output => $output, context => $ctx);
    }
}
