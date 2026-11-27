unit module ScratchAgents::Tools::Search;

use Cro::HTTP::Client;
use JSON::Fast;

#| Search the web using Tavily API.
sub search-web(
    Str :$query!,
    Int :$max-results = 5,
    Str :$topic = 'general',
    Str :$time-range = Str,
) is export {
    try {
        my $api-key = %*ENV<TAVILY_API_KEY> // die 'TAVILY_API_KEY not set';

        my $client = Cro::HTTP::Client.new;

        my %body = (
            api_key     => $api-key,
            query       => $query,
            max_results => $max-results,
            topic       => $topic,
        );
        %body<time_range> = $time-range if $time-range.defined;

        my $resp = await $client.post(
            'https://api.tavily.com/search',
            body => %body,
            content-type => 'application/json',
        );
        my $json = await $resp.body-text;
        my %result = from-json($json);
        return %result<results> // [];

        CATCH {
            default { return "Search error: { .message }" }
        }
    }
}

=begin pod

=head1 NAME

ScratchAgents::Tools::Search - Tavily web search tool

=head1 SYNOPSIS

=begin code :lang<raku>
use ScratchAgents::Tools::Base;
use ScratchAgents::Tools::Search;

my $search-tool = tool(&search-web);
=end code

=head1 DESCRIPTION

Exports C<search-web(Str :$query!, Int :$max-results = 5, Str :$topic = 'general', Str :$time-range)>, which queries the Tavily Search REST API via C<Cro::HTTP::Client> using C<< $*ENV<TAVILY_API_KEY> >>.

=end pod
