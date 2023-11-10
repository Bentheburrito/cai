defmodule LiveModel do
  @moduledoc """
  Create and manage a LiveView model. A model allows you to define your LiveView assigns declaratively, similar to how
  you would use a `` and its `attr/2,3` macro.

  To create a model, import this module and use the `defmodel` macro, like so:

  ```elixir
  defmodule MyAppWeb.MyLive.Model do
    import LiveModel

    defmodel do
      field :user, MyApp.User.t(), required: true
      field :grocery_list, [MyApp.Food.t()], default: []
      field :sale_text, String.t() # defaults to `nil`
    end
  end
  ```

  Then, in your LiveView module:

  ```elixir
  defmodule MyAppWeb.MyLive do
    use MyAppWeb, :live_view

    alias MyAppWeb.MyLive.Model

    # un-import `assign/2,3` and friends that are included in `use MyAppWeb, :live_view` to avoid accidental use.
    # (You should use the model helper functions instead, explained later in this moduledoc)
    import Phoenix.Component, except: [assign: 2, assign: 3, assign_new: 3, update: 3]
    # alternatively, if you don't use other functions in `Phoenix.Component` and you get an "unused import"
    # warning from the above, you can do something like this instead:
    # import Phoenix.Component, only: []

    @impl true
    def mount(_params, %{"user_id" => user_id}, socket) do
      user = MyApp.get_user!(user_id)

      {:ok, Model.assign_new(socket, user)} # assigns a new model struct under the `@model` assign
    end
  ```

  You would then access assigns in your render function/template via `@model.assign`, instead of `@assign`.

  The `defmodel` macro will create a struct and `t()` type for you. It will also create the following helper functions:
  - `new/x`: creates a struct, where arity `x` is the number of required fields plus `1`. Required fields are passed
     as individual arguments to `new/x`, and optional fields are passed in a Keyword list (or another Enumerable like
     a map)
  - `assign_new/x`: similar to `new/x`, but takes the socket as the first argument and assigns the new struct under
    `@model`.
  - `put/2-3`: given a LiveView socket, updates the `:model` assign with the given field(s) and value(s). This function
     is meant to replace use of `Phoenix.Component.assign` in your LiveView
  - `update/2-3`: given a LiveView socket, updates the `:model` assign by passing the current value under `field` to the
    given `updater` function. The result then replaces the original value. This function
     is meant to replace use of `Phoenix.Component.update` in your LiveView

  Please read each function's documentation for more information.

  Much of the implementation of `defmodel` is heavily inspired by Lucas San Román's `typedstruct` macro. You can read
  more about it (and Elixir's AST/macros in general) in their
  [blogpost](https://dorgan.netlify.app/posts/2021/04/the_elixir_ast_typedstruct/).

  The "model" naming scheme is inspired by the [Elm architecture/programming language](https://elm-lang.org/).
  """

  defmacro defmodel(do: ast) do
    fields_ast =
      case ast do
        {:__block__, [], fields} -> fields
        field -> [field]
      end

    fields_data = Enum.map(fields_ast, &get_field_data/1)
    field_names = Enum.map(fields_data, & &1.name)

    enforced_fields =
      for field <- fields_data, field.required do
        field.name
      end

    typespecs =
      Enum.map(fields_data, fn
        %{name: name, typespec: typespec, required: true} ->
          {name, typespec}

        %{name: name, typespec: typespec, default: default} when not is_nil(default) ->
          {name, typespec}

        %{name: name, typespec: typespec} ->
          {
            name,
            {:|, [], [typespec, nil]}
          }
      end)

    fields =
      for %{name: name, default: default} <- fields_data do
        {name, default}
      end

    enforced_field_vars =
      Enum.map(enforced_fields, &(&1 |> Atom.to_string() |> Code.string_to_quoted!()))

    quote location: :keep do
      import Phoenix.Component, only: [assign: 3]

      @type t() :: %__MODULE__{unquote_splicing(typespecs)}
      @enforce_keys unquote(enforced_fields)
      defstruct unquote(fields)

      @doc """
      Create a new model struct.
      """
      def new(unquote_splicing(enforced_field_vars), optional_fields \\ []) do
        struct(
          %__MODULE__{unquote_splicing(Enum.zip(enforced_fields, enforced_field_vars))},
          optional_fields
        )
      end

      @doc """
      Create a new model struct and assigns it to `:model` on the given LiveView socket.
      """
      def assign_new(socket, unquote_splicing(enforced_field_vars), optional_fields \\ []) do
        assign(
          socket,
          :model,
          new(unquote_splicing(enforced_field_vars), optional_fields)
        )
      end

      @doc """
      Updates the model in the assigns of the given `socket`.

      The `value` will be put under `field` in the Model, overwriting any existing value.

      This function will raise if `field` is not a field in your model's `defmodel`
      """
      @spec put(Phoenix.LiveView.Socket.t(), atom(), any()) :: Phoenix.LiveView.Socket.t()
      def put(socket, field, value) when field in unquote(field_names) do
        assign(
          socket,
          :model,
          struct(socket.assigns.model, [{field, value}])
        )
      end

      @doc """
      Updates the model in the assigns of the given `socket`.

      This function is similar to `put/3`, but is used for updating multiple fields at once.

      `fields` should be an `Enumerable` that emits 2-element tuples.

      If the `fields` contains keys that don't exist in the model, they will be ignored.
      """
      @spec put(Phoenix.LiveView.Socket.t(), Enumerable.t({atom(), any()})) ::
              Phoenix.LiveView.Socket.t()
      def put(socket, fields) do
        assign(
          socket,
          :model,
          struct(socket.assigns.model, fields)
        )
      end

      @doc """
      Updates the model in the assigns of the given `socket`.

      `updater` will be called and passed the value under `field`, and the result will replace the original value.

      This function will raise if `field` is not a field in your model's `defmodel`
      """
      @spec update(Phoenix.LiveView.Socket.t(), atom(), function()) :: Phoenix.LiveView.Socket.t()
      def update(socket, field, updater)
          when field in unquote(field_names) and is_function(updater) do
        assign(
          socket,
          :model,
          Map.update!(socket.assigns.model, field, updater)
        )
      end
    end
  end

  defp get_field_data({:field, _meta, [name, typespec]}) do
    get_field_data({:field, [], [name, typespec, []]})
  end

  defp get_field_data({:field, _meta, [name, typespec, opts]}) do
    default = Keyword.get(opts, :default)
    required = Keyword.get(opts, :required, false)

    %{
      name: name,
      typespec: typespec,
      default: default,
      required: required
    }
  end
end
