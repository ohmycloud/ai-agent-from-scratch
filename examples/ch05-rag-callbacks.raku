use v6.d;
use lib 'lib';
use Env::Dotenv;
use ScratchAgents;
use ScratchAgents::Callbacks;
use ScratchAgents::Rag;
use ScratchAgents::Tools::Base;
use ScratchAgents::Tools::Search;

# CH05: RAG Chunking + Vector Search + Search Compressor Callback

my $doc = q:to/END/;
Raku is a member of the Perl family of programming languages.
It supports gradual typing, concurrent promises, junctions, and NativeCall.
AI agents combine LLM reasoning with tool execution and memory systems.
END

my @chunks = fixed-length-chunking($doc, :chunk-size(80), :overlap(20));
say "Chunks: { @chunks.elems }";
say "  - $_" for @chunks;

# When running with live API keys, attach search-compressor to compress search outputs:
# my $agent = Agent.new(
#     model                => LlmClient.new(model => 'gpt-5.5'),
#     tools                => [tool(&search-web)],
#     after-tool-callbacks => [&search-compressor],
# );
