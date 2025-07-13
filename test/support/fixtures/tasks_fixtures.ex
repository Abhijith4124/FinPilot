defmodule Finpilot.TasksFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Finpilot.Tasks` context.
  """

  @doc """
  Generate a task.
  """
  def task_fixture(attrs \\ %{}) do
    {:ok, task} =
      attrs
      |> Enum.into(%{
        context: %{},
        current_summary: "some current_summary",
        is_done: true,
        next_instruction: "some next_instruction",
        task_instruction: "some task_instruction"
      })
      |> Finpilot.Tasks.create_task()

    task
  end



  @doc """
  Generate a instruction.
  """
  def instruction_fixture(attrs \\ %{}) do
    {:ok, instruction} =
      attrs
      |> Enum.into(%{
        actions: %{},
        ai_prompt: "some ai_prompt",
        description: "some description",
        is_active: true,
        name: "some name",
        trigger_conditions: %{}
      })
      |> Finpilot.Tasks.create_instruction()

    instruction
  end
end
