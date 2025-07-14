defmodule FinpilotWeb.Structs.ProcessingContext do
  defstruct [
    :text,
    :user_id,
    :source,
    :metadata,
    :instructions,
    :running_tasks,
    :task,
    :tool_results,
    :timestamp,
    :process_id,
    :node
  ]
end
