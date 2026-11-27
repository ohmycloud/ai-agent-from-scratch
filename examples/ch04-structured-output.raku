use v6.d;
use lib 'lib';
use Env::Dotenv;
use ScratchAgents;

# CH04: Structured Output with `output-type`
# Forces the Agent to finish via the `final_answer` tool and returns a typed Raku object.
# Run offline by default, or pass `--live` to use your configured LLM API.

class BookSummary {
    has Str $.title   is required;
    has Str $.topic   is required;
    has Int $.rating  is required;

    method json-schema(--> Hash) {
        {
            type       => 'object',
            properties => {
                title  => { type => 'string',  description => 'Book title' },
                topic  => { type => 'string',  description => 'Main subject of the book' },
                rating => { type => 'integer', description => 'Relevance score from 1 to 5' },
            },
            required => <title topic rating>,
        }
    }

    method from-hash(%h --> BookSummary) {
        BookSummary.new(
            title  => ~%h<title>,
            topic  => ~%h<topic>,
            rating => (%h<rating> // 5).Int,
        );
    }
}

class MockStructuredModel {
    has Str $.model = 'mock-structured';
    method generate(LlmRequest $req --> LlmResponse) {
        LlmResponse.new(content => [
            ToolCall.new(
                tool-call-id => 'ans_1',
                name         => 'final_answer',
                arguments    => {
                    output => {
                        title  => 'Build an AI Agent from Scratch',
                        topic  => 'Designing ReAct agents, tools, memory, and multi-agent workflows',
                        rating => 5,
                    },
                },
            ),
        ]);
    }
}

my $model = @*ARGS.grep('--live')
    ?? LlmClient.new(model => %*ENV<OPENAI_MODEL> // 'gpt-5.5')
    !! MockStructuredModel.new;

my $agent = Agent.new(
    model        => $model,
    output-type  => BookSummary,
    instructions => 'Summarize the book and return the answer using the final_answer tool.',
);

my $result = $agent.run("Summarize the book 'Build an AI Agent from Scratch'.");
my BookSummary $summary = $result.output;

say "Returned class : { $summary.^name }";
say "Title          : { $summary.title }";
say "Topic          : { $summary.topic }";
say "Rating         : { $summary.rating }/5";
