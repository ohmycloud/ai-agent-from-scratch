use v6.d;
use lib 'lib';
use Env::Dotenv;
use ScratchAgents;
use ScratchAgents::Memory::Session;
use ScratchAgents::Memory::ContextOptimizer;
use ScratchAgents::Tools::Base;

# CH06: Sessions, Human-in-the-Loop Confirmation, and Context Optimization

sub delete_temp_file(Str :$filename!) {
    "Deleted $filename";
}

my $safe-delete = tool(
    &delete_temp_file,
    :requires-confirmation,
    confirmation-message => "Approve deleting '\{arguments}'?",
);

my $sessions = InMemorySessionManager.new;
my $llm      = LlmClient.new(model => %*ENV<OPENAI_MODEL> // 'gpt-5.5');
my $optimizer = ContextOptimizer.new(llm-client => $llm, token-threshold => 30000);

my $agent = Agent.new(
    model                => $llm,
    tools                => [$safe-delete],
    session-manager      => $sessions,
    before-llm-callbacks => [$optimizer],
);

say "Session manager & HITL confirmation agent configured: { $agent.name }";
