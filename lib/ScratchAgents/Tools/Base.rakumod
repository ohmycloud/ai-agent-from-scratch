unit module ScratchAgents::Tools::Base;

use JSON::Fast;
use ScratchAgents::Context;
use ScratchAgents::Tools::Helpers;

#| Abstract base class for all tools.
class BaseTool is export {
    has Str  $.name                         is rw;
    has Str  $.description                  is rw;
    has Hash $.tool-definition              is rw;
    has Bool $.requires-confirmation        = False;
    has Str  $.confirmation-message-template is rw = '';

    my constant DEFAULT-CONFIRMATION-TEMPLATE =
        "The agent wants to execute '\{name}' with arguments: \{arguments}. Do you approve?";

    submethod TWEAK() {
        $!confirmation-message-template = DEFAULT-CONFIRMATION-TEMPLATE
            unless $!confirmation-message-template;
    }

    method get-confirmation-message(%arguments --> Str) {
        my $tool-name = $!name // self.^name;
        $!confirmation-message-template
            .subst('{name}', $tool-name)
            .subst('{arguments}', ~%arguments);
    }

    #| Hook for tools to modify the LlmRequest before it is sent.
    method process-llm-request(ExecutionContext $context, $request) { Nil }

    #| Execute the tool. Must be overridden.
    method execute(ExecutionContext $context, *%kwargs) { ... }

    #| Callable interface.
    method CALL-ME(ExecutionContext $context, *%kwargs) {
        self.execute($context, |%kwargs);
    }
}

#| Wraps a Raku sub as a BaseTool.
class FunctionTool is BaseTool is export {
    has      &.func               is required;
    has Bool $.needs-context      = False;
    has Bool $.sandbox-executable = False;

    submethod TWEAK() {
        $!needs-context = so &!func.signature.params.first({ .name eq '$context' });

        if $!sandbox-executable && $!needs-context {
            die "Tool '{ &!func.name }' cannot be sandbox_executable because it requires 'context' parameter.";
        }

        self.name        = &!func.name unless self.name.defined && self.name.chars;
        self.description = (&!func.WHY // '').Str.trim unless self.description.defined;

        unless self.tool-definition.defined {
            self.tool-definition = self!generate-definition();
        }
    }

    method execute(ExecutionContext $context, *%kwargs) {
        invoke-with-kwargs(&!func, %kwargs, :$context, :pass-context($!needs-context));
    }

    method !generate-definition(--> Hash) {
        my %parameters = function-to-input-schema(&!func);
        format-tool-definition(self.name, self.description // '', %parameters);
    }

    method get-source-code(--> Str) {
        die "Tool '{ self.name }' is not marked as sandbox_executable"
            unless $!sandbox-executable;
        "# Source code for { self.name } (Raku function)";
    }
}

#| Decorator-like sub to create a FunctionTool from a sub.
sub tool(
    &func,
    Str  :$name,
    Str  :$description,
    Bool :$sandbox-executable = False,
    Bool :$requires-confirmation = False,
    Str  :$confirmation-message,
    Hash :$tool-definition,
    --> FunctionTool
) is export {
    FunctionTool.new(
        func                          => &func,
        name                          => $name // &func.name,
        description                   => $description // (&func.WHY // '').Str.trim,
        sandbox-executable            => $sandbox-executable,
        requires-confirmation         => $requires-confirmation,
        confirmation-message-template => $confirmation-message // '',
        tool-definition               => $tool-definition // Hash,
    );
}

=begin pod

=head1 NAME

ScratchAgents::Tools::Base - BaseTool, FunctionTool, and tool factory

=head1 SYNOPSIS

=begin code :lang<raku>
use ScratchAgents::Tools::Base;

#| Greet a user by name.
sub greet(Str :$name! --> Str) { "Hello, $name!" }

my $greet-tool = tool(&greet);
say $greet-tool(ExecutionContext.new, name => 'Raku');
=end code

=head1 DESCRIPTION

Defines the tool abstraction used by C<ScratchAgents::Agent>:

=item C<BaseTool> — Abstract base class with C<name>, C<description>, C<tool-definition>, C<requires-confirmation>, C<confirmation-message-template>, C<.process-llm-request>, C<.execute>, and C<.CALL-ME>.
=item C<FunctionTool> — Wraps any Raku subroutine, inspects its signature to auto-generate OpenAI tool definitions, injects C<$context> if declared, and dispatches both positional and named arguments.
=item C<tool(&func, ...)> — Convenience factory returning a configured C<FunctionTool>.

=end pod
