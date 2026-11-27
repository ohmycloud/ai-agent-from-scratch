use v6.d;
use lib 'lib';
use ScratchAgents;
use ScratchAgents::Tools::AgentTool;
use ScratchAgents::Workflows::Loop;

# CH09: Dynamic Agent Transfer (`sub-agents`), `AgentTool`, and `LoopWorkflow`

class StaticModel {
    has Str $.model = 'demo';
    has Str $.reply is required;
    method generate(LlmRequest $req --> LlmResponse) {
        LlmResponse.new(content => [Message.new(role => 'assistant', content => $!reply)]);
    }
}

# --- Part 1: Dynamic handoff via transfer_to_agent ---
class RouterModel {
    has Str $.model = 'router';
    method generate(LlmRequest $req --> LlmResponse) {
        LlmResponse.new(content => [
            ToolCall.new(
                tool-call-id => 'handoff_1',
                name         => 'transfer_to_agent',
                arguments    => { agent_name => 'raku_specialist' },
            ),
        ]);
    }
}

my $specialist = Agent.new(
    StaticModel.new(reply => 'Use `start` and `Promise.allof` for structured concurrency in Raku.'),
    name        => 'raku_specialist',
    description => 'Answers Raku language and concurrency questions',
);

my $triage = Agent.new(
    RouterModel.new,
    name       => 'triage',
    sub-agents => [$specialist],
);

say "=== 1. Dynamic Agent Transfer ===";
my $handoff-res = $triage.run('How do I run tasks concurrently in Raku?');
say "Handled by sub-agent -> { $handoff-res.output }";

# --- Part 2: Wrapping an Agent as a Tool (`AgentTool`) ---
say "\n=== 2. AgentTool Delegation ===";
my $specialist-tool = AgentTool.new(agent => $specialist);
say "Tool name: { $specialist-tool.name }";
say "Delegated result: " ~ $specialist-tool(ExecutionContext.new, request => 'Concurrency tip?');

# --- Part 3: Iterative Refinement (`LoopWorkflow`) ---
say "\n=== 3. LoopWorkflow Iterative Refinement ===";
my Int $draft-num = 0;
class RefinerModel {
    has Str $.model = 'refiner';
    method generate(LlmRequest $req --> LlmResponse) {
        $draft-num++;
        my $status = $draft-num >= 3 ?? 'APPROVED: Final polished draft.' !! "Draft #$draft-num (needs refinement)";
        LlmResponse.new(content => [Message.new(role => 'assistant', content => $status)]);
    }
}

my $refiner = Agent.new(RefinerModel.new, name => 'refiner');
my $loop = LoopWorkflow.new(
    [$refiner],
    stop-condition => sub ($res, $iter) { ($res.output // '').starts-with('APPROVED:') },
    max-iterations => 5,
);
my $loop-res = $loop.run('Write an intro paragraph.');
say "Stopped after $draft-num iterations -> { $loop-res.output }";
