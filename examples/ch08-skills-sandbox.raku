use v6.d;
use lib 'lib';
use ScratchAgents::Skills;

# CH08: Skills Discovery & Sandbox Tools
my $skills-path = @*ARGS[0] // 'skills';
my @skills      = discover-skills($skills-path);

if @skills {
    say generate-skills-prompt(@skills);
} else {
    say "No skills found in '$skills-path'. Create a subdirectory with a SKILL.md frontmatter file.";
}
