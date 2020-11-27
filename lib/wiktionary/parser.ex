defmodule Wiktionary.Parser do
  @type language :: String.t()

  @type parsed :: %{current_language: String.t() | nil, results: map(), staged: map()}
  @type reducer :: (parsed(), Floki.html_tree() -> parsed())

  @type extract :: {kind, attribute}
  @type kind :: :language_section_start | :part_of_speech_section_start
  @type attribute :: String.t()

  def test_wiktionary_article() do
    url = "https://en.wiktionary.org/wiki/wenn"
    response = HTTPoison.get!(url)
    response.body
  end

  @spec parse_article(article :: String.t()) :: parsed()
  def parse_article(article) do
    {:ok, article} = Floki.parse_document(article)
    article_content = Floki.find(article, "div#mw-content-text")
    [{"div", _attrs, children}] = article_content

    %{current_language: current_language, results: results, staged: staged} =
      fold_children(children, %{current_language: nil, results: %{}, staged: %{}}, fn elem, acc ->
        case language_section_start(elem) do
          {:language_section_start, language_name} ->
            staged_empty? = Map.keys(acc.staged) |> Enum.empty?()

            results =
              if is_nil(acc.current_language) || staged_empty? do
                acc.results
              else
                Map.put(acc.results, acc.current_language, acc.staged)
              end

            %{current_language: language_name, results: results, staged: %{}}

          nil ->
            case part_of_speech_section_start(elem) do
              {:part_of_speech_section_start, part_of_speech} ->
                %{acc | staged: Map.put(acc.staged, :part_of_speech, part_of_speech)}

              _ ->
                acc
            end
        end
      end)

    if staged != %{} do
      Map.put(results, current_language, staged)
      # |> IO.inspect(label: :parser_result)
    else
      results
      # |> IO.inspect(label: :parser_result)
    end
  end

  ## Helper

  @doc false
  @spec language_section_start(Floki.html_tree()) :: extract() | nil
  def language_section_start(elem) do
    case elem do
      # TODO: use id = language to extract them
      {"h2", _attrs, [{"span", span_attrs, [possible_language_name]} | _rest]} ->
        if {"class", "mw-headline"} in span_attrs do
          {:language_section_start, possible_language_name}
        else
          nil
        end

      _ ->
        nil
    end
  end

  @parts_of_speech ~w(Noun Verb Adverb Adjective Pronoun Conjunction Interjection)

  @doc false
  @spec part_of_speech_section_start(Floki.html_tree()) :: extract() | nil
  def part_of_speech_section_start(elem) do
    case elem do
      {tag, _attrs, [{"span", span_attrs, [_possible_part_of_speech]} | _rest]}
      when tag in ["h3", "h4"] ->
        part_of_speech =
          Enum.find_value(span_attrs, fn
            {"id", id} ->
              Enum.find(@parts_of_speech, fn part_of_speech ->
                String.starts_with?(id, part_of_speech)
              end)

            _ ->
              nil
          end)

        if !is_nil(part_of_speech) do
          {:part_of_speech_section_start, part_of_speech}
        else
          nil
        end

      _ ->
        nil
    end
  end

  @doc false
  @spec fold_children(Floki.html_tree(), parsed(), reducer()) :: parsed()
  def fold_children(html_tree, accumulator, reducer)

  def fold_children(children, acc, f) when is_list(children) do
    Enum.reduce(children, acc, fn elem, acc -> fold_children(elem, acc, f) end)
  end

  def fold_children({tag, attrs, children} = node, acc, f)
      when is_binary(tag) and is_list(attrs) do
    acc = f.(node, acc)
    fold_children(children, acc, f)
  end

  def fold_children(text, acc, f) when is_binary(text) do
    f.(text, acc)
  end

  def fold_children({:comment, _}, acc, _f), do: acc
end
