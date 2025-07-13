defmodule Finpilot.TaskRunnerFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Finpilot.TaskRunner` context.
  """

  @doc """
  Generate a task.
  """
  def task_fixture(attrs \\ %{}) do
    {:ok, task} =
      attrs
      |> Enum.into(%{
        context: %{},
        current_stage_summary: "some current_stage_summary",
        is_done: true,
        next_stage_instruction: "some next_stage_instruction",
        task_instruction: "some task_instruction"
      })
      |> Finpilot.TaskRunner.create_task()

    task
  end

  @doc """
  Generate a task_stage.
  """
  def task_stage_fixture(attrs \\ %{}) do
    {:ok, task_stage} =
      attrs
      |> Enum.into(%{
        ai_reasoning: "some ai_reasoning",
        completed_at: ~U[2025-07-12 05:40:00Z],
        error_message: "some error_message",
        stage_name: "some stage_name",
        stage_type: "some stage_type",
        started_at: ~U[2025-07-12 05:40:00Z],
        status: "some status",
        tool_name: "some tool_name",
        tool_params: %{},
        tool_result: %{}
      })
      |> Finpilot.TaskRunner.create_task_stage()

    task_stage
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
      |> Finpilot.TaskRunner.create_instruction()

    instruction
  end
end
