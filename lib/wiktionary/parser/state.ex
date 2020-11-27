defmodule Wiktionary.Parser.State do
  @moduledoc false

  defstruct [:current_language, :current_part_of_speech, :results, :staged]

  @type t :: %__MODULE__{
          current_language: String.t() | nil,
          current_part_of_speech: String.t() | nil,
          # %{
          #   language1 => %{
          #     part_of_speech1 => %{
          #       definitions: [...],
          #       ...
          #     },
          #     part_of_speech2 => %{...},
          #     ...
          #   },
          #   language2 => %{ ... },
          #   ...
          # }
          results: map(),
          # attributes for current {language, part_of_speech}
          staged: map()
        }

  @spec new() :: t()
  def new() do
    %__MODULE__{current_language: nil, current_part_of_speech: nil, results: %{}, staged: %{}}
  end

  @spec finalize(t()) :: map()
  def finalize(%__MODULE__{} = state) do
    IO.inspect(state, label: :state_before_fin)

    put_result_for_language_and_part_of_speech(
      state.results,
      state.current_language,
      state.current_part_of_speech,
      state.staged
    )
    # TODO:
    |> IO.inspect(label: :parser_result)
  end

  @spec put_current_language(t(), String.t()) :: t()
  def put_current_language(%__MODULE__{staged: staged} = state, language_name) do
    results =
      put_result_for_language_and_part_of_speech(
        state.results,
        state.current_language,
        state.current_part_of_speech,
        staged
      )

    %__MODULE__{current_language: language_name, results: results, staged: %{}}
  end

  @spec put_part_of_speech(t(), String.t()) :: t()
  def put_part_of_speech(%__MODULE__{staged: staged} = state, part_of_speech) do
    results =
      put_result_for_language_and_part_of_speech(
        state.results,
        state.current_language,
        state.current_part_of_speech,
        staged
      )

    %__MODULE__{state | current_part_of_speech: part_of_speech, results: results, staged: %{}}
  end

  @spec put_attribute(t(), any(), any()) :: t()
  def put_attribute(state, key, value) do
    %__MODULE__{state | staged: Map.put(state.staged, key, value)}
  end

  ## Helpers

  @doc false
  @spec put_result_for_language_and_part_of_speech(map(), String.t(), String.t(), map()) :: map()
  def put_result_for_language_and_part_of_speech(results, language, part_of_speech, staged) do
    # initial state contains empty part_of_speech, so we shouldn't add anything in that case
    if is_nil(part_of_speech) do
      results
    else
      results = Map.put_new(results, language, %{})

      # sometimes we have several identical parts of speech for the same language,
      # for different word definitions
      if is_nil(results[language][part_of_speech]) do
        put_in(results, [language, part_of_speech], staged)
      else
        # FIXME: handle more than 2 different sections for the same {language, part_of_speech}
        put_in(results, [language, part_of_speech <> "2"], staged)
      end
    end
  end
end
