unit module ScratchAgents::Planning;

use ScratchAgents::Context;
use ScratchAgents::Tools::Base;
use ScratchAgents::Tools::Helpers;

#| A task in the agent's plan.
class Task is export {
    has Str $.content is required;
    has Str $.status  is required where * ~~ 'pending' | 'in_progress' | 'completed';

    method Str(--> Str) {
        given $!status {
            when 'pending'     { "[ ] $!content" }
            when 'in_progress' { "[>] **$!content**" }
            when 'completed'   { "[x] ~~$!content~~" }
            default            { $!content }
        }
    }

    method from-hash(%h --> Task) {
        Task.new(
            content => ~%h<content>,
            status  => ~%h<status>,
        );
    }
}

sub create-tasks-fn(:$tasks! --> Str) {
    $tasks.list.map({ ~($_ ~~ Task ?? $_ !! Task.from-hash($_)) }).join("\n");
}

my constant $CREATE-TASKS-DESC = q:to/END/.trim;
Create or update a task plan.

WHEN TO USE:
- Complex queries requiring multiple steps of research
- Questions that need to combine information from different sources

WHEN NOT TO USE:
- Simple questions answerable with a single search
- Tasks with obvious, straightforward procedures

HOW TO USE:
- Regenerate the entire task list with updated statuses
- Mark completed tasks as 'completed'
- Mark the next task to work on as 'in_progress'
- Keep future tasks as 'pending'
END

my constant %CREATE-TASKS-DEF = format-tool-definition(
    'create_tasks',
    $CREATE-TASKS-DESC,
    {
        type       => 'object',
        properties => {
            tasks => {
                type  => 'array',
                items => {
                    type       => 'object',
                    properties => {
                        content => { type => 'string' },
                        status  => { type => 'string', enum => <pending in_progress completed> },
                    },
                    required => <content status>,
                },
            },
        },
        required => ['tasks'],
    },
);

#| Tool instance for creating/updating a task plan.
my $CREATE-TASKS-TOOL = FunctionTool.new(
    func            => &create-tasks-fn,
    name            => 'create_tasks',
    description     => $CREATE-TASKS-DESC,
    tool-definition => %CREATE-TASKS-DEF,
);

multi sub create-tasks(--> FunctionTool) is export { $CREATE-TASKS-TOOL }
multi sub create-tasks(ExecutionContext $context, *%kwargs) is export {
    $CREATE-TASKS-TOOL($context, |%kwargs);
}

sub reflection-fn(Str :$analysis!, Bool :$need-replan = False --> Str) {
    if $need-replan {
        return "Reflection recorded (REPLAN NEEDED): $analysis";
    }
    "Reflection recorded: $analysis";
}

my constant $REFLECTION-DESC = q:to/END/.trim;
Pause and analyze progress before continuing.

WHEN TO USE:
1. PROGRESS REVIEW - After completing a meaningful step
2. ERROR ANALYSIS - When a tool fails or returns unexpected results
3. RESULT SYNTHESIS - When combining information from multiple sources
4. SELF CHECK - Before providing final answer

WHEN NOT TO USE:
- After every single tool call (excessive overhead)
- During simple, straightforward operations
- When everything is proceeding as expected
END

my constant %REFLECTION-DEF = format-tool-definition(
    'reflection',
    $REFLECTION-DESC,
    {
        type       => 'object',
        properties => {
            analysis    => { type => 'string',  description => 'Your assessment of current situation and next direction' },
            need-replan => { type => 'boolean', description => 'Set True if the current plan needs modification' },
        },
        required => ['analysis'],
    },
);

#| Tool instance for agent reflection.
my $REFLECTION-TOOL = FunctionTool.new(
    func            => &reflection-fn,
    name            => 'reflection',
    description     => $REFLECTION-DESC,
    tool-definition => %REFLECTION-DEF,
);

multi sub reflection(--> FunctionTool) is export { $REFLECTION-TOOL }
multi sub reflection(ExecutionContext $context, *%kwargs) is export {
    $REFLECTION-TOOL($context, |%kwargs);
}
