unit module ScratchAgents::Rag;

use JSON::Fast;
use Cro::HTTP::Client;

#| Convert text(s) to embedding vectors via OpenAI-compatible embeddings API.
sub get-embeddings(
    $texts,
    Str :$model    = 'text-embedding-3-small',
    Str :$api-key  = %*ENV<OPENAI_API_KEY>  // '',
    Str :$base-url = %*ENV<OPENAI_BASE_URL> // 'https://api.openai.com/v1',
    --> Array
) is export {
    my @inputs = $texts ~~ Positional ?? @$texts.map(~*) !! [~$texts];

    my $client = Cro::HTTP::Client.new(
        headers => [
            Authorization => "Bearer $api-key",
        ],
    );

    my $resp = await $client.post(
        "$base-url/embeddings",
        body         => { input => @inputs, model => $model },
        content-type => 'application/json',
    );
    my %data = from-json(await $resp.body-text);
    my @items = (%data<data> // []).sort({ .<index> // 0 });
    @items.map({ (.<embedding> // []).Array }).Array;
}

#| Split text into fixed-length chunks with optional overlap.
sub fixed-length-chunking(
    Str  $text,
    Int  $pos-chunk-size?,
    Int  $pos-overlap?,
    Int :$chunk-size,
    Int :$overlap,
    --> Array
) is export {
    my Int $cs = $chunk-size // $pos-chunk-size // 500;
    my Int $ov = $overlap    // $pos-overlap    // 50;

    if $cs <= 0 || !(0 <= $ov < $cs) {
        die "Require chunk_size > 0 and 0 <= overlap < chunk_size";
    }

    my @chunks;
    my $start = 0;
    my $len   = $text.chars;

    while $start < $len {
        my $end   = min($start + $cs, $len);
        my $chunk = $text.substr($start, $end - $start).trim;
        @chunks.push($chunk) if $chunk.chars;
        $start = $end < $len ?? $end - $ov !! $end;
    }

    @chunks;
}

#| Compute cosine similarity between two numeric vectors in pure Raku.
sub cosine-similarity(@a, @b --> Num) is export {
    return 0e0 unless @a.elems && @a.elems == @b.elems;
    my Num $dot    = 0e0;
    my Num $norm-a = 0e0;
    my Num $norm-b = 0e0;
    for ^@a.elems -> $i {
        my Num $va = @a[$i].Num;
        my Num $vb = @b[$i].Num;
        $dot    += $va * $vb;
        $norm-a += $va * $va;
        $norm-b += $vb * $vb;
    }
    my Num $denom = sqrt($norm-a) * sqrt($norm-b);
    $denom == 0e0 ?? 0e0 !! ($dot / $denom);
}

#| Find the most similar chunks to the query using cosine similarity.
sub vector-search(
    Str  $query,
         @chunks,
         @chunk-embeddings,
    Int  $pos-top-k?,
    Int :$top-k,
        :&embedder = &get-embeddings,
    --> Array
) is export {
    my Int $k = $top-k // $pos-top-k // 3;
    return [] unless @chunks.elems && @chunk-embeddings.elems;

    my @q-emb = @(&embedder([$query])[0]);
    my @scored;
    for ^min(@chunks.elems, @chunk-embeddings.elems) -> $i {
        @scored.push({
            chunk      => @chunks[$i],
            similarity => cosine-similarity(@q-emb, @(@chunk-embeddings[$i])),
        });
    }

    @scored.sort({ -.<similarity> }).head($k).Array;
}

=begin pod

=head1 NAME

ScratchAgents::Rag - Embeddings, fixed-length chunking, and vector search

=head1 SYNOPSIS

=begin code :lang<raku>
use ScratchAgents::Rag;

my @chunks = fixed-length-chunking($document, :chunk-size(500), :overlap(50));
my @embs   = get-embeddings(@chunks);
my @hits   = vector-search('lunar perigee', @chunks, @embs, :top-k(3));
=end code

=head1 DESCRIPTION

Provides Retrieval-Augmented Generation (RAG) building blocks without external numerical libraries:

=item C<< get-embeddings($texts, :$model, :$api-key, :$base-url --> Array) >> — Calls an OpenAI-compatible C</embeddings> endpoint via C<Cro::HTTP::Client>.
=item C<< fixed-length-chunking(Str $text, :$chunk-size = 500, :$overlap = 50 --> Array) >> — Splits text into overlapping character windows (validates C<< chunk-size > 0 >> and C<< 0 <= overlap < chunk-size >>).
=item C<< cosine-similarity(@a, @b --> Num) >> — Pure-Raku cosine similarity between two numeric vectors.
=item C<< vector-search(Str $query, @chunks, @chunk-embeddings, :$top-k = 3, :&embedder --> Array) >> — Ranks chunks by cosine similarity to the query embedding.

=end pod
