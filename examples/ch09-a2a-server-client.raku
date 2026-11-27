use v6.d;
use lib 'lib';
use Cro::HTTP::Router;
use Cro::HTTP::Server;
use ScratchAgents;
use ScratchAgents::A2AServer;
use ScratchAgents::Remote;

# CH09: Self-contained A2A (Agent-to-Agent) Server (Cro::HTTP::Server) + RemoteAgent Client Demo
# Exposes `/.well-known/agent.json` and `POST /tasks/send` backed by `MathAgentExecutor`,
# then discovers and queries it using `RemoteAgent`.

class MathMockModel {
    has Str $.model = 'math-a2a';
    method generate(LlmRequest $req --> LlmResponse) {
        LlmResponse.new(content => [
            Message.new(role => 'assistant', content => 'The answer computed remotely is 42.'),
        ]);
    }
}

my $math-agent = Agent.new(
    MathMockModel.new,
    name        => 'remote_math_agent',
    description => 'Solves math problems over A2A',
);
my $executor = MathAgentExecutor.new(agent => $math-agent);

my $application = route {
    get -> '.well-known', 'agent.json' {
        content 'application/json', {
            name        => $math-agent.name,
            description => $math-agent.description,
        };
    }

    post -> 'tasks', 'send' {
        request-body -> %rpc {
            my @queue;
            $executor.execute({ message => %rpc<params><message> }, @queue);
            content 'application/json', {
                jsonrpc => '2.0',
                result  => { artifacts => @queue },
            };
        }
    }
};

my $port   = 21888 + ($*PID % 1000);
my $server = Cro::HTTP::Server.new(host => '127.0.0.1', :$port, :$application);
$server.start;
LEAVE { $server.stop }

my $remote = RemoteAgent.new(base-url => "http://127.0.0.1:$port");
say "Discovered RemoteAgent : { $remote.name }";
say "Description            : { $remote.description }";

my $res = $remote.run('Compute 6 * 7');
say "Remote A2A Output      : { $res.output }";
