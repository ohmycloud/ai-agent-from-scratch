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
