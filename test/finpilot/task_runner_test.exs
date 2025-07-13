defmodule Finpilot.TaskRunnerTest do
  use Finpilot.DataCase

  alias Finpilot.TaskRunner

  describe "tasks" do
    alias Finpilot.TaskRunner.Task

    import Finpilot.TaskRunnerFixtures

    @invalid_attrs %{context: nil, task_instruction: nil, current_stage_summary: nil, next_stage_instruction: nil, is_done: nil}

    test "list_tasks/0 returns all tasks" do
      task = task_fixture()
      assert TaskRunner.list_tasks() == [task]
    end

    test "get_task!/1 returns the task with given id" do
      task = task_fixture()
      assert TaskRunner.get_task!(task.id) == task
    end

    test "create_task/1 with valid data creates a task" do
      valid_attrs = %{context: %{}, task_instruction: "some task_instruction", current_stage_summary: "some current_stage_summary", next_stage_instruction: "some next_stage_instruction", is_done: true}

      assert {:ok, %Task{} = task} = TaskRunner.create_task(valid_attrs)
      assert task.context == %{}
      assert task.task_instruction == "some task_instruction"
      assert task.current_stage_summary == "some current_stage_summary"
      assert task.next_stage_instruction == "some next_stage_instruction"
      assert task.is_done == true
    end

    test "create_task/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = TaskRunner.create_task(@invalid_attrs)
    end

    test "update_task/2 with valid data updates the task" do
      task = task_fixture()
      update_attrs = %{context: %{}, task_instruction: "some updated task_instruction", current_stage_summary: "some updated current_stage_summary", next_stage_instruction: "some updated next_stage_instruction", is_done: false}

      assert {:ok, %Task{} = task} = TaskRunner.update_task(task, update_attrs)
      assert task.context == %{}
      assert task.task_instruction == "some updated task_instruction"
      assert task.current_stage_summary == "some updated current_stage_summary"
      assert task.next_stage_instruction == "some updated next_stage_instruction"
      assert task.is_done == false
    end

    test "update_task/2 with invalid data returns error changeset" do
      task = task_fixture()
      assert {:error, %Ecto.Changeset{}} = TaskRunner.update_task(task, @invalid_attrs)
      assert task == TaskRunner.get_task!(task.id)
    end

    test "delete_task/1 deletes the task" do
      task = task_fixture()
      assert {:ok, %Task{}} = TaskRunner.delete_task(task)
      assert_raise Ecto.NoResultsError, fn -> TaskRunner.get_task!(task.id) end
    end

    test "change_task/1 returns a task changeset" do
      task = task_fixture()
      assert %Ecto.Changeset{} = TaskRunner.change_task(task)
    end
  end

  describe "task_stages" do
    alias Finpilot.TaskRunner.TaskStage

    import Finpilot.TaskRunnerFixtures

    @invalid_attrs %{status: nil, started_at: nil, stage_name: nil, stage_type: nil, tool_name: nil, tool_params: nil, tool_result: nil, ai_reasoning: nil, completed_at: nil, error_message: nil}

    test "list_task_stages/0 returns all task_stages" do
      task_stage = task_stage_fixture()
      assert TaskRunner.list_task_stages() == [task_stage]
    end

    test "get_task_stage!/1 returns the task_stage with given id" do
      task_stage = task_stage_fixture()
      assert TaskRunner.get_task_stage!(task_stage.id) == task_stage
    end

    test "create_task_stage/1 with valid data creates a task_stage" do
      valid_attrs = %{status: "some status", started_at: ~U[2025-07-12 05:40:00Z], stage_name: "some stage_name", stage_type: "some stage_type", tool_name: "some tool_name", tool_params: %{}, tool_result: %{}, ai_reasoning: "some ai_reasoning", completed_at: ~U[2025-07-12 05:40:00Z], error_message: "some error_message"}

      assert {:ok, %TaskStage{} = task_stage} = TaskRunner.create_task_stage(valid_attrs)
      assert task_stage.status == "some status"
      assert task_stage.started_at == ~U[2025-07-12 05:40:00Z]
      assert task_stage.stage_name == "some stage_name"
      assert task_stage.stage_type == "some stage_type"
      assert task_stage.tool_name == "some tool_name"
      assert task_stage.tool_params == %{}
      assert task_stage.tool_result == %{}
      assert task_stage.ai_reasoning == "some ai_reasoning"
      assert task_stage.completed_at == ~U[2025-07-12 05:40:00Z]
      assert task_stage.error_message == "some error_message"
    end

    test "create_task_stage/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = TaskRunner.create_task_stage(@invalid_attrs)
    end

    test "update_task_stage/2 with valid data updates the task_stage" do
      task_stage = task_stage_fixture()
      update_attrs = %{status: "some updated status", started_at: ~U[2025-07-13 05:40:00Z], stage_name: "some updated stage_name", stage_type: "some updated stage_type", tool_name: "some updated tool_name", tool_params: %{}, tool_result: %{}, ai_reasoning: "some updated ai_reasoning", completed_at: ~U[2025-07-13 05:40:00Z], error_message: "some updated error_message"}

      assert {:ok, %TaskStage{} = task_stage} = TaskRunner.update_task_stage(task_stage, update_attrs)
      assert task_stage.status == "some updated status"
      assert task_stage.started_at == ~U[2025-07-13 05:40:00Z]
      assert task_stage.stage_name == "some updated stage_name"
      assert task_stage.stage_type == "some updated stage_type"
      assert task_stage.tool_name == "some updated tool_name"
      assert task_stage.tool_params == %{}
      assert task_stage.tool_result == %{}
      assert task_stage.ai_reasoning == "some updated ai_reasoning"
      assert task_stage.completed_at == ~U[2025-07-13 05:40:00Z]
      assert task_stage.error_message == "some updated error_message"
    end

    test "update_task_stage/2 with invalid data returns error changeset" do
      task_stage = task_stage_fixture()
      assert {:error, %Ecto.Changeset{}} = TaskRunner.update_task_stage(task_stage, @invalid_attrs)
      assert task_stage == TaskRunner.get_task_stage!(task_stage.id)
    end

    test "delete_task_stage/1 deletes the task_stage" do
      task_stage = task_stage_fixture()
      assert {:ok, %TaskStage{}} = TaskRunner.delete_task_stage(task_stage)
      assert_raise Ecto.NoResultsError, fn -> TaskRunner.get_task_stage!(task_stage.id) end
    end

    test "change_task_stage/1 returns a task_stage changeset" do
      task_stage = task_stage_fixture()
      assert %Ecto.Changeset{} = TaskRunner.change_task_stage(task_stage)
    end
  end

  describe "instructions" do
    alias Finpilot.TaskRunner.Instruction

    import Finpilot.TaskRunnerFixtures

    @invalid_attrs %{name: nil, description: nil, trigger_conditions: nil, actions: nil, ai_prompt: nil, is_active: nil}

    test "list_instructions/0 returns all instructions" do
      instruction = instruction_fixture()
      assert TaskRunner.list_instructions() == [instruction]
    end

    test "get_instruction!/1 returns the instruction with given id" do
      instruction = instruction_fixture()
      assert TaskRunner.get_instruction!(instruction.id) == instruction
    end

    test "create_instruction/1 with valid data creates a instruction" do
      valid_attrs = %{name: "some name", description: "some description", trigger_conditions: %{}, actions: %{}, ai_prompt: "some ai_prompt", is_active: true}

      assert {:ok, %Instruction{} = instruction} = TaskRunner.create_instruction(valid_attrs)
      assert instruction.name == "some name"
      assert instruction.description == "some description"
      assert instruction.trigger_conditions == %{}
      assert instruction.actions == %{}
      assert instruction.ai_prompt == "some ai_prompt"
      assert instruction.is_active == true
    end

    test "create_instruction/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = TaskRunner.create_instruction(@invalid_attrs)
    end

    test "update_instruction/2 with valid data updates the instruction" do
      instruction = instruction_fixture()
      update_attrs = %{name: "some updated name", description: "some updated description", trigger_conditions: %{}, actions: %{}, ai_prompt: "some updated ai_prompt", is_active: false}

      assert {:ok, %Instruction{} = instruction} = TaskRunner.update_instruction(instruction, update_attrs)
      assert instruction.name == "some updated name"
      assert instruction.description == "some updated description"
      assert instruction.trigger_conditions == %{}
      assert instruction.actions == %{}
      assert instruction.ai_prompt == "some updated ai_prompt"
      assert instruction.is_active == false
    end

    test "update_instruction/2 with invalid data returns error changeset" do
      instruction = instruction_fixture()
      assert {:error, %Ecto.Changeset{}} = TaskRunner.update_instruction(instruction, @invalid_attrs)
      assert instruction == TaskRunner.get_instruction!(instruction.id)
    end

    test "delete_instruction/1 deletes the instruction" do
      instruction = instruction_fixture()
      assert {:ok, %Instruction{}} = TaskRunner.delete_instruction(instruction)
      assert_raise Ecto.NoResultsError, fn -> TaskRunner.get_instruction!(instruction.id) end
    end

    test "change_instruction/1 returns a instruction changeset" do
      instruction = instruction_fixture()
      assert %Ecto.Changeset{} = TaskRunner.change_instruction(instruction)
    end
  end
end
