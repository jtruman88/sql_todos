require 'sinatra'
require 'sinatra/content_for'
require 'tilt/erubis'

require_relative "database_persistence"

configure do
  enable :sessions
  set :session_secret, 'secret'
  set :erb, :escape_html => true
end

configure(:development) do
  require 'sinatra/reloader'
  also_reload "database_persistence.rb"
end

before do
  @storage = DatabasePersistence.new(logger)
end

after do
  @storage.disconnect
end

helpers do
  def completed?(list)
    list[:todos_count] >= 1 && list[:todos_remaining_count] == 0
  end
  
  def list_class(list)
    'complete' if completed?(list)
  end
  
  def no_todos(todos)
    'complete' if todos.count == 0
  end
  
  def sort_lists(lists, &block)
    incomplete = {}
    complete = {}
    
    lists.each do |list|
      if completed?(list)
        complete[list] = list[:id]
      else
        incomplete[list] = list[:id]
      end
    end
    
    incomplete.each(&block)
    complete.each(&block)
  end
  
  def sort_todos(todos, &block)
    incomplete = {}
    complete = {}
    
    todos.each do |todo|
      if todo[:completed]
        complete[todo] = todo[:id]
      else
        incomplete[todo] = todo[:id]
      end
    end
    
    incomplete.each(&block)
    complete.each(&block)
  end
end

# Return an error if list name is invalid. Return nil if valid.
def check_for_error(list_name)
  error = if !(1..100).cover?(list_name.size)
            'The list name must be between 1 and 100 characters.'
          elsif @storage.all_lists.any? { |list| list[:name] == list_name }
            'The list name must be unique.'
          end

  error
end

# Return an error if todo name is invalid. Return nil if valid.
def check_todo_error(todo)
  unless (1..100).cover?(todo.length)
    'Todo must be between 1 and 100 characters.'
  end
end

get '/' do
  redirect '/lists'
end


# Verifies a valid list id is given
def load_list(id)
  list = @storage.find_list(id)
  return list if list
  
  session[:error] = "The specified list was not found."
  redirect '/lists'
end

# GET   /lists                    -> view all lists
# GET   /lists/new                -> new list form
# POST  /lists                    -> create new list
# GET   /lists/1                  -> view a single list
# GET   /lists/1/edit             -> edit existing todo list name
# POST  /lists/1                  -> rename an existing list
# POST  /lists/1/destroy          -> delete an existing list
# POST  /lists/1/todos            -> add a todo to a list
# POST  /lists/1/todos/1/destroy  -> delete a todo from a list
# POST  /lists/1/todos/1          -> update status of todo
# POST  /lists/1/complete_all     -> complete all todos in a list    

# View all the lists
get '/lists' do
  @lists = @storage.all_lists
  erb :lists, layout: :layout
end

# Render the new list form
get '/lists/new' do
  erb :new_list, layout: :layout
end

# Create a new list
post '/lists' do
  list_name = params[:list_name].strip

  error = check_for_error(list_name)
  if error
    session[:error] = error
    erb :new_list, layout: :layout
  else
    @storage.create_new_list(list_name)
    session[:success] = 'The list has been successfully created.'
    redirect '/lists'
  end
end

# View a single list
get '/lists/:number' do
  @num = params[:number].to_i
  @list = load_list(@num)
  @todos = @storage.find_todos_for_list(@num)
  
  erb :list, layout: :layout
end

# Edit existing todo list name
get '/lists/:number/edit' do
  @num = params[:number].to_i
  @list = load_list(@num)
  
  erb :edit_list
end

# Rename an existing list
post '/lists/:number' do
  list_name = params[:list_name].strip
  @num = params[:number].to_i
  @list = load_list(@num)

  error = check_for_error(list_name)
  if error
    session[:error] = error
    erb :edit_list, layout: :layout
  else
    @storage.update_list_name(@num, list_name)
    session[:success] = 'The list has been updated.'
    redirect "/lists/#{@num}"
  end
end

# Delete an existing list
post '/lists/:number/destory' do
  num = params[:number].to_i
  @storage.delete_list(num)
  if env['HTTP_X_REQUESTED_WITH'] == 'XMLHttpRequest'
    '/lists'
  else
    session[:success] = "The list has been deleted."
    redirect "/lists"
  end
end

# Add a todo to a list
post '/lists/:list_num/todos' do
  @list_id = params[:list_num].to_i
  todo_name = params[:todo].strip
  @list = load_list(@list_id)
  @todos = @list[:todos]
  
  error = check_todo_error(todo_name)
  if error
    session[:error] = error
    erb :list, layout: :layout
  else
    @storage.create_new_todo(@list_id, todo_name)
    session[:success] = 'The todo was added.'
    redirect "/lists/#{@list_id}"
  end
end

# Delete a todo from a list
post '/lists/:list_num/todos/:todo_num/destroy' do
  todo_num = params[:todo_num].to_i
  list_num = params[:list_num].to_i
  list = load_list(list_num)
  
  @storage.delete_todo_from_list(list_num, todo_num)

  if env['HTTP_X_REQUESTED_WITH'] == 'XMLHttpRequest'
    status 204
  else
    session[:success] = 'The todo has been deleted.'
    redirect "/lists/#{list_num}"
  end
end

# Update status of todo
post '/lists/:list_num/todos/:todo_num' do
  list_num = params[:list_num].to_i
  todo_num = params[:todo_num].to_i
  list = load_list(list_num)
  is_completed = params[:completed] == 'true'
  
  @storage.update_todo_status(list_num, todo_num, is_completed)
  session[:success] = 'The todo has been updated.'
  redirect "/lists/#{list_num}"
end

# Mark all todos on a list complete
post '/lists/:num/complete_all' do
  list_id = params[:num].to_i
  @storage.mark_all_todos_complete(list_id)
  
  session[:success] = 'All todos have been completed.'
  redirect "/lists/#{list_id}"
end
