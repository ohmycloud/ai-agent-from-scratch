unit module ScratchAgents::Tools::FileTools;

use Cro::HTTP::Client;
use JSON::Fast;
use MIME::Base64;

my constant @TEXT-EXTENSIONS = <.txt .raku .rakumod .py .js .json .md .html .css .xml .yaml .yml .log .sh>;
my constant @SPREADSHEET-EXTENSIONS = <.xlsx .xls .csv>;
my constant @IMAGE-EXTENSIONS = <.png .jpg .jpeg .gif .webp .bmp>;
my constant @AUDIO-EXTENSIONS = <.mp3 .wav .m4a .flac .ogg .webm>;
my constant @PDF-EXTENSIONS = <.pdf>;

#| Extract a zip file to the specified directory.
sub unzip-file(Str :$zip-path!, Str :$extract-to = Str --> Str) is export {
    my $zp = $zip-path.IO;
    return "File not found: $zip-path" unless $zp.e;

    my $target = $extract-to.defined ?? $extract-to.IO !! $zp.parent.child($zp.basename.subst(/ '.' <-[.]>+ $ /, ''));
    $target.mkdir;

    my $proc = run 'unzip', '-o', ~$zp, '-d', ~$target, :out, :err;
    my @files = $proc.out.slurp(:close).lines.grep(/ 'inflating:' | 'extracting:' /).map({ .trim.subst(/^ \S+ ':' \s* /, '') });

    my $result = "Extracted { @files.elems } files to $target/\n\nContents:\n";
    for @files.head(20) -> $f {
        $result ~= "  - $f\n";
    }
    $result ~= "  ... and { @files.elems - 20 } more files\n" if @files > 20;
    $result;
}

#| List files and directories in the given path.
sub list-files(Str :$path = '.' --> Str) is export {
    my $p = $path.IO;
    return "Path not found: $path" unless $p.e;
    return "Not a directory: $path" unless $p.d;

    my @items;
    for $p.dir.sort({ .basename }) -> $item {
        next if $item.basename.starts-with('.');
        @items.push($item.d ?? "{ $item.basename }/" !! $item.basename);
    }

    my @dirs  = @items.grep(*.ends-with('/'));
    my @files = @items.grep(!*.ends-with('/'));

    my $result = "Directory: $path\n";
    for |@dirs, |@files -> $item {
        $result ~= "  $item\n";
    }
    $result;
}

#| Read file content. Supports txt, raku, json, md, csv, xlsx.
sub read-file(Str :$file-path!, Int :$start-line = 1, Int :$end-line = -1 --> Str) is export {
    my $path = $file-path.IO;
    return "File not found: $file-path" unless $path.e;

    my $ext = $path.extension ?? ".{$path.extension.lc}" !! '';

    if $ext eq any(@TEXT-EXTENSIONS) {
        return read-text-file($file-path, $start-line, $end-line);
    } elsif $ext eq '.csv' {
        return read-csv($file-path);
    } elsif $ext eq any(@SPREADSHEET-EXTENSIONS) {
        return read-excel($file-path);
    } else {
        return read-text-file($file-path, $start-line, $end-line);
    }
}

#| Analyze an image, audio, or PDF file using LLM.
sub read-media-file(Str :$file-path!, Str :$query! --> Str) is export {
    my $ext = $file-path.IO.extension.defined ?? ".{$file-path.IO.extension.lc}" !! '';

    if $ext eq any(@IMAGE-EXTENSIONS) {
        return analyze-image($file-path, $query);
    } elsif $ext eq any(@AUDIO-EXTENSIONS) {
        return analyze-audio($file-path, $query);
    } elsif $ext eq any(@PDF-EXTENSIONS) {
        return analyze-pdf($file-path, $query);
    } else {
        return "Unsupported media format: $ext";
    }
}

sub read-text-file(Str $file-path, Int $start-line, Int $end-line --> Str) {
    my @lines = $file-path.IO.lines;
    my $start-idx = max(0, $start-line - 1);
    my $end-idx   = $end-line == -1 ?? @lines.elems - 1 !! min($end-line - 1, @lines.elems - 1);

    my @selected = @lines[$start-idx .. $end-idx];
    @selected.kv.map(-> $i, $line {
        sprintf('%4d | %s', $start-line + $i, $line)
    }).join("\n");
}

sub read-csv(Str $file-path --> Str) {
    # Simple CSV reader without pandas dependency
    my @lines = $file-path.IO.lines;
    return '' unless @lines;
    @lines.join("\n");
}

sub read-excel(Str $file-path --> Str) {
    try {
        require Spreadsheet::XLSX;
        my $workbook = Spreadsheet::XLSX.load($file-path.IO);
        my $sheet = $workbook.worksheets[0];

        my @rows;
        for $sheet.cells -> @row {
            @rows.push(@row.map({ .defined ?? ~$_ !! '' }).join("\t"));
        }
        return @rows.join("\n");

        CATCH {
            default { return "Error reading spreadsheet: { .message }" }
        }
    }
}

sub analyze-image(Str $file-path, Str $query --> Str) {
    my $image-data = MIME::Base64.encode($file-path.IO.slurp(:bin));
    my $ext = $file-path.IO.extension.lc;
    my $media-type = $ext eq 'jpg' ?? 'image/jpeg' !! "image/$ext";

    # Call OpenAI vision API
    my $client = Cro::HTTP::Client.new(
        headers => [
            Authorization => "Bearer { %*ENV<OPENAI_API_KEY> // '' }",
        ],
    );

    my %body = (
        model    => 'gpt-5.5',
        messages => [{
            role    => 'user',
            content => [
                { type => 'text', text => $query },
                { type => 'image_url', image_url => {
                    url => "data:$media-type;base64,$image-data"
                }},
            ],
        },],
    );

    my $resp = await $client.post(
        'https://api.openai.com/v1/chat/completions',
        body => %body,
        content-type => 'application/json',
    );
    my %result = from-json(await $resp.body-text);
    %result<choices>[0]<message><content>;
}

sub analyze-audio(Str $file-path, Str $query --> Str) {
    my $audio-data = MIME::Base64.encode($file-path.IO.slurp(:bin));
    my $ext = $file-path.IO.extension.lc;

    my $client = Cro::HTTP::Client.new(
        headers => [
            Authorization => "Bearer { %*ENV<OPENAI_API_KEY> // '' }",
        ],
    );

    my %body = (
        model    => 'gpt-audio',
        messages => [{
            role    => 'user',
            content => [
                { type => 'text', text => $query },
                { type => 'input_audio', input_audio => {
                    data   => $audio-data,
                    format => $ext,
                }},
            ],
        },],
    );

    my $resp = await $client.post(
        'https://api.openai.com/v1/chat/completions',
        body => %body,
        content-type => 'application/json',
    );
    my %result = from-json(await $resp.body-text);
    %result<choices>[0]<message><content>;
}

sub analyze-pdf(Str $file-path, Str $query --> Str) {
    # Use pdftotext (poppler) for text extraction
    my $proc = run 'pdftotext', $file-path, '-', :out, :err;
    my $text-content = $proc.out.slurp(:close);
    $text-content = $text-content.substr(0, 3000) if $text-content.chars > 3000;

    # Use pdftoppm for page images (first 5 pages)
    my @images;
    for 1..5 -> $page {
        my $img-proc = run 'pdftoppm', '-png', '-f', ~$page, '-l', ~$page, '-singlefile', $file-path, '-', :out, :err;
        my $img-bytes = $img-proc.out.slurp(:close, :bin);
        last unless $img-bytes.bytes;
        @images.push(MIME::Base64.encode($img-bytes));
    }

    my $client = Cro::HTTP::Client.new(
        headers => [
            Authorization => "Bearer { %*ENV<OPENAI_API_KEY> // '' }",
        ],
    );

    my @content = { type => 'text', text => "$query\n\nExtracted text:\n$text-content" };
    for @images -> $img-b64 {
        @content.push({ type => 'image_url', image_url => { url => "data:image/png;base64,$img-b64" } });
    }

    my %body = (
        model    => 'gpt-5.5',
        messages => [{ role => 'user', content => @content },],
    );

    my $resp = await $client.post(
        'https://api.openai.com/v1/chat/completions',
        body => %body,
        content-type => 'application/json',
    );
    my %result = from-json(await $resp.body-text);
    %result<choices>[0]<message><content>;
}
