use v6.d;
use lib 'lib';
use Env::Dotenv;
use ScratchAgents;
use ScratchAgents::Tools::Base;
use ScratchAgents::Tools::Calculator;
use ScratchAgents::Tools::Search;
use ScratchAgents::Utils;

# CH03 & CH04: ReAct Agent with Calculator & Web Search tools

my $agent = Agent.new(
    model        => LlmClient.new(model => %*ENV<OPENAI_MODEL> // 'gpt-5.5'),
    tools        => [tool(&calculator), tool(&search-web)],
    instructions => 'You are a helpful research assistant. Use tools when needed.',
    max-steps    => 8,
);

my $prompt = @*ARGS[0] // 'What is 128 * 42? Use the calculator tool.';
my $result = $agent.run($prompt, :verbose);

say "\nFinal Answer:\n{ $result.output }";
display-trace($result.context);
