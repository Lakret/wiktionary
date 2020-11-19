defmodule Wiktionary.Parser do
  @type language :: String.t()

  @type level :: non_neg_integer()
  @type accumulator :: any()
  @type reducer :: (level(), accumulator(), Floki.html_tree() -> accumulator())
  @type tree_with_levels :: {level(), tree_with_levels()} | Floki.html_tree()

  def test_wiktionary_article() do
    url = "https://en.wiktionary.org/wiki/Angst"
    response = HTTPoison.get!(url)
    response.body
  end

  # tree = {"span", [{"class", "mw-headline"}, {"id", "German"}], ["German"]}
  # Parser.to_html(tree) |> IO.puts()
  #
  # tree = [{1, {"span", [{"class", "mw-headline"}, {"id", "German"}], ["German"]}}]

  @spec to_html(tree_with_levels()) :: String.t()
  def to_html(html_tree) do
    level_to_use =
      case html_tree do
        {level, _} when is_number(level) -> level
        [{level, _} | _] when is_number(level) -> level
        _ -> raise "Cannot convert empty tree to HTML"
      end

    to_html(level_to_use, html_tree)
  end

  def to_html(level_to_use, {level, _tree}) when level_to_use < level, do: ""

  def to_html(level_to_use, {_level, tags}) when is_list(tags) do
    Enum.map(tags, &to_html/1) |> Enum.join()
  end

  def to_html(_level_to_use, {_level, {tag, [], []}}), do: "<#{tag}></#{tag}>"

  def to_html(_level_to_use, {_level, {tag, attributes, children}}) do
    attributes =
      case attributes do
        [] ->
          ""

        _ ->
          attributes = Enum.map(attributes, &to_html_attribute/1) |> Enum.join(" ")
          " #{attributes}"
      end

    children = Enum.map(children, &to_html/1) |> Enum.join()

    "<#{tag}#{attributes}>#{children}</#{tag}>"
  end

  def to_html(_level_to_use, {_level, text}) when is_binary(text), do: text

  @doc false
  def to_html_attribute({name, value}) do
    ~s(#{name}="#{value}")
  end

  @spec parse_article(article :: String.t()) :: %{language() => tree_with_levels()}
  def parse_article(article) do
    {:ok, article} = Floki.parse_document(article)
    article_content = Floki.find(article, "div#mw-content-text")
    [{"div", _attrs, children}] = article_content

    {language_name, staged, language_blocks} =
      fold_children(0, children, {nil, [], nil}, fn level,
                                                    elem,
                                                    {language_name, staged, result} ->
        case elem do
          {"h2", _attrs, [{"span", span_attrs, [new_language_name]} | _rest]} ->
            if Enum.any?(span_attrs, fn attr -> attr == {"class", "mw-headline"} end) do
              case result do
                nil ->
                  {new_language_name, [{level, elem}], []}

                result when is_list(result) ->
                  {new_language_name, [], result ++ [{language_name, Enum.reverse(staged)}]}
              end
            else
              {language_name, [{level, elem} | staged], result}
            end

          _ ->
            {language_name, [{level, elem} | staged], result}
        end
      end)

    language_blocks = language_blocks ++ [{language_name, Enum.reverse(staged)}]

    language_blocks |> Enum.into(%{})
  end

  @spec fold_children(level(), Floki.html_tree(), accumulator(), reducer()) :: accumulator()
  def fold_children(level, html_tree, accumulator, reducer)

  def fold_children(level, children, acc, f) when is_list(children) do
    Enum.reduce(children, acc, fn elem, acc -> fold_children(level + 1, elem, acc, f) end)
  end

  def fold_children(level, {tag, attrs, children} = node, acc, f)
      when is_binary(tag) and is_list(attrs) do
    acc = f.(level, node, acc)
    fold_children(level + 1, children, acc, f)
  end

  def fold_children(level, text, acc, f) when is_binary(text) do
    f.(level, text, acc)
  end

  def fold_children(_level, {:comment, _}, acc, _f), do: acc
end
