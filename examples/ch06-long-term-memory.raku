use v6.d;
use lib 'lib';
use ScratchAgents;
use ScratchAgents::Memory::Session;
use ScratchAgents::Memory::LongTerm;

# CH06: Long-Term Memory (SQLite via DBIish) + MemoryTool + Multi-Turn Sessions
# Runs completely offline with a mock LLM & mock embedder to show the full lifecycle:
# 1. Turn 1 solves a task and persists structured TaskMemory into SQLite.
# 2. Turn 2 queries a related question; MemoryTool automatically injects <PAST_EXPERIENCES>.

class MemoryDemoClient is LlmClient {
    has Int $!turn = 0;

    method generate(LlmRequest $req --> LlmResponse) {
        $!turn++;
        my $saw-memory = so $req.instructions.first({ .contains('<PAST_EXPERIENCES>') });
        my $reply = $saw-memory
            ?? 'Recalled past experience from SQLite memory: perigee distance is 356,500 km.'
            !! 'Found moon perigee distance: 356,500 km.';
        LlmResponse.new(content => [Message.new(role => 'assistant', content => $reply)]);
    }

    method ask(Str $prompt, :$response-format = Nil) {
        if $prompt.contains('Analyze the following execution history') {
            return TaskMemory.new(
                task-summary => 'Find closest Earth-Moon distance (perigee)',
                approach     => 'Lookup astronomy reference for lunar perigee',
                final-answer => '356,500 km',
                is-correct   => True,
            );
        }
        DuplicateCheckResult.new(decision => 'ADD', reason => 'New task record');
    }
}

my &simple-embedder = sub ($texts) {
    my @list = $texts ~~ Positional ?? @$texts !! [~$texts];
    @list.map({ .lc.contains('moon' | 'perigee') ?? [1.0, 0.0] !! [0.0, 1.0] }).Array;
};

my $llm      = MemoryDemoClient.new(model => 'mock-memory');
my $sessions = InMemorySessionManager.new;
my $memory   = TaskMemoryManager.new(
    llm-client => $llm,
    db-path    => ':memory:',   # pass a file path like 'memories.sqlite3' for disk persistence
    embedder   => &simple-embedder,
);

my $agent = Agent.new(
    model           => $llm,
    session-manager => $sessions,
    memory-manager  => $memory,
);

say "=== Run 1 (saves TaskMemory to SQLite) ===";
my $r1 = $agent.run('What is the closest distance to the moon?', session-id => 'demo-session');
say "Output: { $r1.output }";

say "\n=== Run 2 (new session; MemoryTool auto-injects past experience) ===";
my $r2 = $agent.run('Remind me of the moon perigee distance.', session-id => 'new-session');
say "Output: { $r2.output }";
