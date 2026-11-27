unit module ScratchAgents::Skills;

use YAMLish;

#| Information about a discovered skill.
class SkillInfo is export {
    has Str      $.name        is required;
    has Str      $.description is required;
    has IO::Path $.path        is required;
}

#| Extract YAML frontmatter from a markdown file.
sub parse-frontmatter(Str $content --> Hash) is export {
    my $match = ($content ~~ / ^ '---' \h* \n (.*?) \n '---' /);
    return {} unless $match;

    my $yaml-text = ~$match[0];
    try {
        my $parsed = load-yaml($yaml-text);
        return $parsed.Hash if $parsed ~~ Associative;
        CATCH { default { } }
    }

    my %result;
    for $yaml-text.lines -> $line {
        if $line.contains(':') {
            my ($k, $v) = $line.split(':', 2);
            %result{$k.trim} = $v.trim.subst(/^ <["']> | <["']> $ /, '', :g);
        }
    }
    %result;
}

#| Load skill info from a directory containing SKILL.md.
sub load-skill(IO::Path $skill-dir --> SkillInfo) is export {
    my $skill-md = $skill-dir.child('SKILL.md');
    return SkillInfo unless $skill-md.e;

    my $content     = $skill-md.slurp(:enc<utf8>);
    my %frontmatter = parse-frontmatter($content);

    my $name        = %frontmatter<name>;
    my $description = %frontmatter<description>;
    return SkillInfo unless $name && $description;

    SkillInfo.new(name => ~$name, description => ~$description, path => $skill-dir);
}

#| Discover all skills in a directory (each subdirectory with SKILL.md).
sub discover-skills($skills-path --> Array) is export {
    my $skills-dir = $skills-path ~~ IO::Path ?? $skills-path !! (~$skills-path).IO;
    return [] unless $skills-dir.e && $skills-dir.d;

    my @skills;
    for $skills-dir.dir.sort({ .basename }) -> $item {
        next if !$item.d || $item.basename.starts-with('.');
        my $skill = load-skill($item);
        @skills.push($skill) if $skill.defined;
    }
    @skills;
}

#| Generate a prompt describing available skills for code execution agents.
sub generate-skills-prompt(@skills, Str :$sandbox-path = '/home/user/skills' --> Str) is export {
    return '' unless @skills;

    my @lines = (
        '## Available Skills',
        'The following skills are available in the sandbox environment:',
        '',
    );

    for @skills -> $skill {
        @lines.push("### { $skill.name }");
        @lines.push("- Description: { $skill.description }");
        @lines.push("- Path: $sandbox-path/{ $skill.name }/");
        @lines.push("- Read the SKILL.md for usage instructions: $sandbox-path/{ $skill.name }/SKILL.md");
        @lines.push('');
    }

    @lines.push(
        'You can import and use these skills in your Python code. '
        ~ 'Read the SKILL.md file first to understand how to use each skill.'
    );

    @lines.join("\n");
}
