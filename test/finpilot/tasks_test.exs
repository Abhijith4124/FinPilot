defmodule Finpilot.TasksTest do
  use Finpilot.DataCase

  alias Finpilot.Tasks

  describe "tasks" do
    alias Finpilot.Tasks.Task

    import Finpilot.TasksFixtures

    @invalid_attrs %{context: nil, task_instruction: nil, current_summary: nil, next_instruction: nil, is_done: nil}

    test "list_tasks/0 returns all tasks" do
      task = task_fixture()
      assert Tasks.list_tasks() == [task]
    end

    test "get_task!/1 returns the task with given id" do
      task = task_fixture()
      assert Tasks.get_task!(task.id) == task
    end

    test "create_task/1 with valid data creates a task" do
      valid_attrs = %{context: %{}, task_instruction: "some task_instruction", current_summary: "some current_summary", next_instruction: "some next_instruction", is_done: true}

      assert {:ok, %Task{} = task} = Tasks.create_task(valid_attrs)
      assert task.context == %{}
      assert task.task_instruction == "some task_instruction"
      assert task.current_summary == "some current_summary"
      assert task.next_instruction == "some next_instruction"
      assert task.is_done == true
    end

    test "create_task/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Tasks.create_task(@invalid_attrs)
    end

    test "update_task/2 with valid data updates the task" do
      task = task_fixture()
      update_attrs = %{context: %{}, task_instruction: "some updated task_instruction", current_summary: "some updated current_summary", next_instruction: "some updated next_instruction", is_done: false}

      assert {:ok, %Task{} = task} = Tasks.update_task(task, update_attrs)
      assert task.context == %{}
      assert task.task_instruction == "some updated task_instruction"
      assert task.current_summary == "some updated current_summary"
      assert task.next_instruction == "some updated next_instruction"
      assert task.is_done == false
    end

    test "update_task/2 with invalid data returns error changeset" do
      task = task_fixture()
      assert {:error, %Ecto.Changeset{}} = Tasks.update_task(task, @invalid_attrs)
      assert task == Tasks.get_task!(task.id)
    end

    test "delete_task/1 deletes the task" do
      task = task_fixture()
      assert {:ok, %Task{}} = Tasks.delete_task(task)
      assert_raise Ecto.NoResultsError, fn -> Tasks.get_task!(task.id) end
    end

    test "change_task/1 returns a task changeset" do
      task = task_fixture()
      assert %Ecto.Changeset{} = Tasks.change_task(task)
    end
  end



  describe "instructions" do
    alias Finpilot.Tasks.Instruction

    import Finpilot.TasksFixtures

    @invalid_attrs %{name: nil, description: nil, trigger_conditions: nil, actions: nil, ai_prompt: nil, is_active: nil}

    test "list_instructions/0 returns all instructions" do
      instruction = instruction_fixture()
      assert Tasks.list_instructions() == [instruction]
    end

    test "get_instruction!/1 returns the instruction with given id" do
      instruction = instruction_fixture()
      assert Tasks.get_instruction!(instruction.id) == instruction
    end

    test "create_instruction/1 with valid data creates a instruction" do
      valid_attrs = %{name: "some name", description: "some description", trigger_conditions: %{}, actions: %{}, ai_prompt: "some ai_prompt", is_active: true}

      assert {:ok, %Instruction{} = instruction} = Tasks.create_instruction(valid_attrs)
      assert instruction.name == "some name"
      assert instruction.description == "some description"
      assert instruction.trigger_conditions == %{}
      assert instruction.actions == %{}
      assert instruction.ai_prompt == "some ai_prompt"
      assert instruction.is_active == true
    end

    test "create_instruction/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Tasks.create_instruction(@invalid_attrs)
    end

    test "update_instruction/2 with valid data updates the instruction" do
      instruction = instruction_fixture()
      update_attrs = %{name: "some updated name", description: "some updated description", trigger_conditions: %{}, actions: %{}, ai_prompt: "some updated ai_prompt", is_active: false}

      assert {:ok, %Instruction{} = instruction} = Tasks.update_instruction(instruction, update_attrs)
      assert instruction.name == "some updated name"
      assert instruction.description == "some updated description"
      assert instruction.trigger_conditions == %{}
      assert instruction.actions == %{}
      assert instruction.ai_prompt == "some updated ai_prompt"
      assert instruction.is_active == false
    end

    test "update_instruction/2 with invalid data returns error changeset" do
      instruction = instruction_fixture()
      assert {:error, %Ecto.Changeset{}} = Tasks.update_instruction(instruction, @invalid_attrs)
      assert instruction == Tasks.get_instruction!(instruction.id)
    end

    test "delete_instruction/1 deletes the instruction" do
      instruction = instruction_fixture()
      assert {:ok, %Instruction{}} = Tasks.delete_instruction(instruction)
      assert_raise Ecto.NoResultsError, fn -> Tasks.get_instruction!(instruction.id) end
    end

    test "change_instruction/1 returns a instruction changeset" do
      instruction = instruction_fixture()
      assert %Ecto.Changeset{} = Tasks.change_instruction(instruction)
    end
  end
end
