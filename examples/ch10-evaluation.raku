use v6.d;
use lib 'lib';
use ScratchAgents::Eval::Gaia;
use ScratchAgents::Eval::Prompts;

# CH10: Evaluation helpers and GAIA scoring
my $pred = '  42 ';
my $gold = '42';
say "Exact match check ('$pred' vs '$gold'): { is-correct($pred, $gold) }";
say "Provider for 'anthropic/claude-sonnet-4': { get-provider('anthropic/claude-sonnet-4') }";
say "\nRelevancy Judge Prompt Template:\n$ANSWER-RELEVANCY-PROMPT";
