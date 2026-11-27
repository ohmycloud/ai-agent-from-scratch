unit module ScratchAgents::Memory::LongTerm;

use DBIish;
use JSON::Fast;
use UUID;
use ScratchAgents::Context;
use ScratchAgents::Llm;
use ScratchAgents::Rag;
use ScratchAgents::Types;

#| Structured memory for GAIA problem-solving records.
class TaskMemory is export {
    has Str  $.task-summary   is required;
    has Str  $.approach       is required;
    has Str  $.final-answer   is required;
    has Bool $.is-correct     is required;
    has Str  $.error-analysis = Str;

    #| Generate text for vector search.
    method to-embedding-text(--> Str) {
        "Task: $!task-summary";
    }

    method to-hash(--> Hash) {
        {
            task_summary   => $!task-summary,
            approach       => $!approach,
            final_answer   => $!final-answer,
            is_correct     => $!is-correct,
            error_analysis => $!error-analysis // Nil,
        }
    }

    method from-hash(%h --> TaskMemory) {
        my $err = %h<error_analysis> // %h<error-analysis>;
        TaskMemory.new(
            task-summary   => ~(%h<task_summary>   // %h<task-summary>   // ''),
            approach       => ~(%h<approach>       // ''),
            final-answer   => ~(%h<final_answer>   // %h<final-answer>   // ''),
            is-correct     => ?(%h<is_correct>     // %h<is-correct>     // False),
            error-analysis => ($err.defined && ~$err ne '') ?? ~$err !! Str,
        );
    }

    method json-schema(--> Hash) {
        {
            type       => 'object',
            properties => {
                task_summary   => { type => 'string',  description => 'What the problem asked' },
                approach       => { type => 'string',  description => 'Methods and tools used to solve it' },
                final_answer   => { type => 'string',  description => "The agent's submitted answer" },
                is_correct     => { type => 'boolean', description => 'Whether the answer was correct' },
                error_analysis => { type => 'string',  description => 'Why the attempt failed, if it did' },
            },
            required => <task_summary approach final_answer is_correct>,
        }
    }
}

#| Result of duplicate check.
class DuplicateCheckResult is export {
    has Str $.decision is required;  # ADD or SKIP
    has Str $.reason   is required;

    method from-hash(%h --> DuplicateCheckResult) {
        DuplicateCheckResult.new(
            decision => ~(%h<decision> // 'ADD'),
            reason   => ~(%h<reason>   // ''),
        );
    }

    method json-schema(--> Hash) {
        {
            type       => 'object',
            properties => {
                decision => { type => 'string', description => 'ADD (new information) or SKIP (duplicate)' },
                reason   => { type => 'string', description => 'Explanation for the decision' },
            },
            required => <decision reason>,
        }
    }
}

my constant $TASK-MEMORY-EXTRACTION-PROMPT = q:to/END/;
Analyze the following execution history and extract a structured task memory.

Execution History:
{execution_history}

Extract:
- task_summary: What the problem asked
- approach: Methods and tools used to solve it
- final_answer: The agent's submitted answer
- is_correct: Whether the answer was correct (true or false)
- error_analysis: If incorrect, explain why; otherwise leave null
END

my constant $DUPLICATE-CHECK-PROMPT = q:to/END/;
Compare the new memory against existing memories to determine if it's a duplicate.

Existing memories:
{existing_memories}

New memory:
{new_memory}

Respond with one of:
- ADD: This is new information that should be stored
- SKIP: Similar information already exists, no need to store

Judgment criteria:
- Same problem with different approach or different result counts as new information
- Same problem with same approach and same result is a duplicate
END

#| Memory manager backed by SQLite (via DBIish) and cosine similarity search.
class TaskMemoryManager is export {
    has LlmClient $.llm-client      is required;
    has Str       $.collection-name = 'task_memories';
    has Str       $.db-path         = ':memory:';
    has           &.embedder        = &get-embeddings;
    has           $!dbh;
    has Str       $!table-name;

    submethod TWEAK() {
        $!table-name = $!collection-name.subst(/ <-[a..z A..Z 0..9 _]> /, '_', :g);
        $!dbh = DBIish.connect('SQLite', database => $!db-path);
        $!dbh.execute(qq:to/SQL/);
            CREATE TABLE IF NOT EXISTS $!table-name (
                id             TEXT PRIMARY KEY,
                document       TEXT NOT NULL,
                task_summary   TEXT NOT NULL,
                approach       TEXT NOT NULL,
                final_answer   TEXT NOT NULL,
                is_correct     INTEGER NOT NULL,
                error_analysis TEXT NOT NULL DEFAULT '',
                embedding      TEXT NOT NULL
            )
        SQL
    }

    method !extract-memory(Str $execution-history --> TaskMemory) {
        my $prompt = $TASK-MEMORY-EXTRACTION-PROMPT.subst('{execution_history}', $execution-history);
        try {
            my $res = $!llm-client.ask($prompt, response-format => TaskMemory.json-schema);
            return $res ~~ TaskMemory ?? $res !! TaskMemory.from-hash($res);
            CATCH {
                default {
                    note "Memory extraction failed: { .message }";
                    return TaskMemory;
                }
            }
        }
    }

    method !format-execution-history(@events --> Str) {
        my @lines;
        for @events -> $event {
            for $event.content -> $item {
                given $item {
                    when Message    { @lines.push("[{ .role }]: { .content }") }
                    when ToolCall   { @lines.push("[Tool Call]: { .name }({ .arguments })") }
                    when ToolResult {
                        my $preview = .content.elems ?? (~.content[0]).substr(0, 500) !! '';
                        @lines.push("[Tool Result]: { .name } -> $preview");
                    }
                }
            }
        }
        @lines.join("\n");
    }

    method !is-duplicate(TaskMemory $new-memory, @existing --> Bool) {
        return False unless @existing;

        my @existing-texts = @existing.map({
            "task_summary: { .task-summary }, - approach: { .approach }, is_correct: { .is-correct }"
        });

        my $prompt = $DUPLICATE-CHECK-PROMPT
            .subst('{existing_memories}', @existing-texts.join("\n"))
            .subst('{new_memory}',
                "task_summary: { $new-memory.task-summary }, "
                ~ "approach: { $new-memory.approach }, "
                ~ "is_correct: { $new-memory.is-correct }"
            );

        try {
            my $res = $!llm-client.ask($prompt, response-format => DuplicateCheckResult.json-schema);
            my $check = $res ~~ DuplicateCheckResult ?? $res !! DuplicateCheckResult.from-hash($res);
            return $check.decision eq 'SKIP';
            CATCH { default { return False } }
        }
    }

    #| Extract and save memory from execution context. Returns memory ID or Str if skipped.
    method save(ExecutionContext $context --> Str) {
        my $history = self!format-execution-history($context.events);
        my $memory  = self!extract-memory($history);
        return Str unless $memory.defined;

        my @existing = self.search($memory.to-embedding-text, :top-k(3));
        return Str if self!is-duplicate($memory, @existing);

        my $memory-id = ~UUID.new(:version(4));
        my $doc       = $memory.to-embedding-text;
        my @emb       = @((&!embedder)([$doc])[0]);
        my $emb-json  = to-json(@emb, :!pretty);

        my $sth = $!dbh.prepare(qq:to/SQL/);
            INSERT INTO $!table-name
                (id, document, task_summary, approach, final_answer, is_correct, error_analysis, embedding)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        SQL
        $sth.execute(
            $memory-id,
            $doc,
            $memory.task-summary,
            $memory.approach,
            $memory.final-answer,
            $memory.is-correct ?? 1 !! 0,
            $memory.error-analysis // '',
            $emb-json,
        );
        $memory-id;
    }

    #| Search for memories related to the query using cosine similarity.
    method search(Str $query, Int :$top-k = 5 --> Array) {
        my $sth = $!dbh.prepare(qq:to/SQL/);
            SELECT task_summary, approach, final_answer, is_correct, error_analysis, embedding
            FROM $!table-name
        SQL
        $sth.execute();
        my @rows = $sth.allrows(:array-of-hash);
        return [] unless @rows;

        my @q-emb = @((&!embedder)([$query])[0]);
        my @scored;
        for @rows -> %row {
            my @emb = @(from-json(%row<embedding>));
            my $sim = cosine-similarity(@q-emb, @emb);
            my $mem = TaskMemory.new(
                task-summary   => %row<task_summary>,
                approach       => %row<approach>,
                final-answer   => %row<final_answer>,
                is-correct     => ?%row<is_correct>,
                error-analysis => (%row<error_analysis> // '') ne '' ?? %row<error_analysis> !! Str,
            );
            @scored.push({ memory => $mem, similarity => $sim });
        }

        @scored.sort({ -.<similarity> }).head($top-k).map({ .<memory> }).Array;
    }
}

=begin pod

=head1 NAME

ScratchAgents::Memory::LongTerm - SQLite-backed long-term task memory with vector similarity search

=head1 SYNOPSIS

=begin code :lang<raku>
use ScratchAgents::Llm;
use ScratchAgents::Memory::LongTerm;

my $manager = TaskMemoryManager.new(
    llm-client => LlmClient.new(model => 'gpt-5.5'),
    db-path    => 'task_memories.sqlite3',
);

my @similar = $manager.search('lunar perigee distance', :top-k(3));
=end code

=head1 DESCRIPTION

Replaces ChromaDB with C<DBIish> (SQLite) plus pure-Raku cosine similarity from C<ScratchAgents::Rag>:

=item C<TaskMemory> — Structured record of a completed task (C<task-summary>, C<approach>, C<final-answer>, C<is-correct>, C<error-analysis>).
=item C<DuplicateCheckResult> — Structured LLM decision (C<ADD> or C<SKIP>) with rationale.
=item C<TaskMemoryManager> — Extracts memories from C<ExecutionContext.events> via C<LlmClient.ask>, checks semantic duplicates, stores embeddings as JSON in SQLite (defaults to C<:memory:>), and retrieves top-K matches via C<.search>.

=end pod
