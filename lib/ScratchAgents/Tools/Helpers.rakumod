unit module ScratchAgents::Tools::Helpers;

use JSON::Fast;

#| Convert a Raku sub's signature to a JSON Schema for tool parameters.
sub function-to-input-schema(&func --> Hash) is export {
    my %properties;
    my @required;

    for &func.signature.params -> $param {
        next if $param.name eq '$self' | '%_' | '@_' | '$context';

        my $name = $param.named
            ?? ($param.named_names[0] // $param.name.substr(1))
            !! $param.name.substr(1);
        next unless $name;

        my %prop;
        given $param.type {
            when Int                  { %prop<type> = 'integer' }
            when Num | Rat | Numeric | Real { %prop<type> = 'number' }
            when Bool                 { %prop<type> = 'boolean' }
            when Positional | Array   { %prop<type> = 'array'   }
            when Associative | Hash   { %prop<type> = 'object'  }
            default                   { %prop<type> = 'string'  }
        }
        %prop<description> = ($param.WHY // "Parameter: $name").Str.trim;

        %properties{$name} = %prop;

        unless $param.optional || $param.default.defined {
            @required.push($name);
        }
    }

    my %schema = type => 'object', properties => %properties;
    %schema<required> = @required if @required;
    %schema;
}

#| Invoke a Raku sub dynamically with a Hash of named/positional arguments.
sub invoke-with-kwargs(&func, %kwargs, :$context = Nil, Bool :$pass-context = False) is export {
    my @pos;
    my %named = %kwargs;

    for &func.signature.params -> $p {
        next if $p.name eq '$self' | '%_' | '@_';
        if $pass-context && $p.name eq '$context' {
            if $p.named {
                %named<context> = $context;
            } else {
                @pos.push($context);
            }
            next;
        }
        if !$p.named {
            my $pname = $p.name.substr(1);
            if %named{$pname}:exists {
                @pos.push(%named{$pname}:delete);
            }
        }
    }

    &func(|@pos, |%named);
}

#| Format a tool definition in the OpenAI function calling format.
sub format-tool-definition(Str $name, Str $description, %parameters --> Hash) is export {
    {
        type     => 'function',
        function => {
            name        => $name,
            description => $description,
            parameters  => %parameters,
        }
    }
}

#| Convert a Raku sub to an OpenAI-format tool definition.
sub function-to-tool-definition(&func --> Hash) is export {
    my $name        = &func.name;
    my $description = (&func.WHY // "Function: $name").Str.trim;
    my %parameters  = function-to-input-schema(&func);
    format-tool-definition($name, $description, %parameters);
}

#| Execute a tool call using a tool_box mapping.
sub tool-execution(%tool-box, $tool-call --> Str) is export {
    my $func-name = $tool-call<function><name>;
    unless %tool-box{$func-name}:exists {
        return "Error: Unknown tool '$func-name'";
    }

    try {
        my %args = from-json($tool-call<function><arguments>);
        my $result = invoke-with-kwargs(%tool-box{$func-name}, %args);
        return ~$result;
        CATCH {
            default { return "Error executing $func-name: {.message}" }
        }
    }
}
