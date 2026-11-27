unit module ScratchAgents;

need ScratchAgents::Types;
need ScratchAgents::Context;
need ScratchAgents::Llm;
need ScratchAgents::Agent;

my constant Message          is export := ScratchAgents::Types::Message;
my constant ToolCall         is export := ScratchAgents::Types::ToolCall;
my constant ToolResult       is export := ScratchAgents::Types::ToolResult;
my constant Event            is export := ScratchAgents::Types::Event;
my constant ContentItem      is export := ScratchAgents::Types::ContentItem;
sub         deep-copy(|c)    is export { ScratchAgents::Types::deep-copy(|c) }

my constant ExecutionContext is export := ScratchAgents::Context::ExecutionContext;
my constant AgentResult      is export := ScratchAgents::Context::AgentResult;
my constant PendingToolCall  is export := ScratchAgents::Context::PendingToolCall;
my constant ToolConfirmation is export := ScratchAgents::Context::ToolConfirmation;

my constant LlmClient        is export := ScratchAgents::Llm::LlmClient;
my constant LlmRequest       is export := ScratchAgents::Llm::LlmRequest;
my constant LlmResponse      is export := ScratchAgents::Llm::LlmResponse;
sub         build-messages(|c) is export { ScratchAgents::Llm::build-messages(|c) }

my constant Agent            is export := ScratchAgents::Agent::Agent;
