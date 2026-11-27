unit module ScratchAgents::Tools::Calculator;

#| Perform basic arithmetic operations (operator: add/+, subtract/-, multiply/*, divide//).
sub calculator(Str :$operator!, Num(Cool) :$first-number!, Num(Cool) :$second-number! --> Num) is export {
    given $operator {
        when 'add'      | '+' { $first-number + $second-number }
        when 'subtract' | '-' { $first-number - $second-number }
        when 'multiply' | '*' { $first-number * $second-number }
        when 'divide'   | '/' {
            die "Cannot divide by zero" if $second-number == 0;
            $first-number / $second-number;
        }
        default { die "Unknown operator: $operator" }
    }
}

=begin pod

=head1 NAME

ScratchAgents::Tools::Calculator - Basic arithmetic tool

=head1 SYNOPSIS

=begin code :lang<raku>
use ScratchAgents::Tools::Base;
use ScratchAgents::Tools::Calculator;

my $calc = tool(&calculator);
say $calc(ExecutionContext.new, operator => '*', first-number => 128, second-number => 42);
=end code

=head1 DESCRIPTION

Exports C<< calculator(Str :$operator!, Num(Cool) :$first-number!, Num(Cool) :$second-number! --> Num) >>, supporting C<add>/C<+>, C<subtract>/C<->, C<multiply>/C<*>, and C<divide>/C</> (raising an exception on division by zero or unknown operators).

=end pod
