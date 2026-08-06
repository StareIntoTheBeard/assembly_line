# AssemblyLine

I kinda like rewrote langchain in elixir 

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `assembly_line` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:assembly_line, "~> 1.0.0"}
  ]
end
```

## Current Feature Set
* Dynamic multi-step planning 
* Intent detection with routing to tool calls
* Job/prompt requirement tracking and persistence
* Parallel job execution via GenStage
* In-memory schema backed conversation context storage, distributable via Horde
* Sharable, user-aware agent powered chat sessions
* Predefined pipelines with predefined steps
* Arbitrary pipelines with predefined steps
* Multi-model, multi-cloud support, extendable by adapter
  * OpenAI API
    * ChatGPT
    * Dall-E
    * OpenAI Assistants
  * Claude
  * Groq
  * Bedrock Foundation Models
    * Claude
    * Stability AI
    * Jurassic
    * LLaMa
    * Agents
* Async steps
* LiveView support
* Model/Agent routing via PhoneBook
  * Customizable feature flags by adapter, configurable in application
* Conversation logging records all activity to live AI
  * MongoDB support
* Basic training jobs with tagging
* Pipeline planning from a prompt
* Arbitrary pipelines with adhoc steps

## Planned Features
* Job monitoring
* Query management
* Job queues/restarts
* Additional vendor models support as needed
* Alternate models on a restarted job
* Training jobs
  * Ability to select training method
  * Ability to review/alter tagging
