unit module ScratchAgents::Memory::Session;

use ScratchAgents::Types;

#| Container for persistent conversation state across multiple run() calls.
class Session is export {
    has Str      $.session-id is required;
    has Str      $.user-id    = Str;
    has          @.events     is rw;
    has          %.state      is rw;
    has DateTime $.created-at = DateTime.now;
    has DateTime $.updated-at is rw = DateTime.now;
}

#| Abstract base class for session management.
class BaseSessionManager is export {
    #| Create a new session.
    method create(Str $session-id, Str :$user-id = Str --> Session) { ... }

    #| Retrieve a session by ID. Returns undefined Session type object if not found.
    method get(Str $session-id --> Session) { ... }

    #| Persist session changes to storage.
    method save(Session $session --> Nil) { ... }

    #| Get existing session or create a new one.
    method get-or-create(Str $session-id, Str :$user-id = Str --> Session) {
        my $session = self.get($session-id);
        $session = self.create($session-id, :$user-id) unless $session.defined;
        $session;
    }
}

#| In-memory session storage for development and testing.
class InMemorySessionManager is BaseSessionManager is export {
    has %!sessions;

    #| Create a new session.
    method create(Str $session-id, Str :$user-id = Str --> Session) {
        die "Session $session-id already exists" if %!sessions{$session-id}:exists;

        my $session = Session.new(:$session-id, :$user-id);
        %!sessions{$session-id} = $session;
        $session;
    }

    #| Retrieve a session by ID.
    method get(Str $session-id --> Session) {
        %!sessions{$session-id} // Session;
    }

    #| Save session to storage.
    method save(Session $session --> Nil) {
        $session.updated-at = DateTime.now;
        %!sessions{$session.session-id} = $session;
        Nil;
    }
}
