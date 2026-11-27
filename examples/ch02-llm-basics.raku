use v6.d;
use lib 'lib';
use Env::Dotenv;
use ScratchAgents;

# CH02: Calling an LLM directly with LlmClient (Env::Dotenv auto-loads .env if present)

my $client = LlmClient.new(model => %*ENV<OPENAI_MODEL> // 'gpt-5.5');
my $answer = $client.ask('Explain what an AI agent ReAct loop is in 3 sentences.');
say $answer;
