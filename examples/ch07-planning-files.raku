use v6.d;
use lib 'lib';
use Env::Dotenv;
use ScratchAgents;
use ScratchAgents::Planning;
use ScratchAgents::Tools::Base;
use ScratchAgents::Tools::FileTools;

# CH07: Planning, Reflection, and File / Media Tools

my $agent = Agent.new(
    model        => LlmClient.new(model => %*ENV<OPENAI_MODEL> // 'gpt-5.5'),
    tools        => [create-tasks, reflection, tool(&list-files), tool(&read-file)],
    instructions => 'Break complex problems down with create_tasks and review progress via reflection.',
);

say "Planning agent configured with tools: " ~ $agent.tools.map(*.name).join(', ');
