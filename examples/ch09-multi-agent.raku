use v6.d;
use lib 'lib';
use ScratchAgents;
use ScratchAgents::Workflows::Sequential;
use ScratchAgents::Workflows::Parallel;
use ScratchAgents::Workflows::Loop;

# CH09: Multi-Agent Workflows (Sequential, Parallel, Loop) & Agent Transfer
class EchoModel {
    has Str $.model = 'demo';
    has Str $.reply is required;
    method generate(LlmRequest $req --> LlmResponse) {
        LlmResponse.new(content => [Message.new(role => 'assistant', content => $!reply)]);
    }
}

my $researcher = Agent.new(EchoModel.new(reply => 'Gathered 3 key facts.'), name => 'researcher');
my $writer     = Agent.new(EchoModel.new(reply => 'Synthesized final report.'), name => 'writer');

my $pipeline = SequentialWorkflow.new([$researcher, $writer]);
my $seq-res  = $pipeline.run('Write a brief report on Raku.');
say "Sequential Output: { $seq-res.output }";

my $parallel = ParallelWorkflow.new([$researcher, $writer]);
my $par-res  = $parallel.run('Analyze Raku from multiple angles.');
say "\nParallel Output:\n{ $par-res.output }";
