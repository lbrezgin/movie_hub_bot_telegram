require 'telegram/bot'
require 'dotenv/load'

TOKEN = ENV['BOT_TOKEN']

DATA_FILE = 'movies_data.txt'
user_states = {}

def update_movie_data(movie_name, property, new_value)
  data = []
  if File.exist?(DATA_FILE)
    data = File.readlines(DATA_FILE).map(&:chomp)
  end
  
  updated_data = data.map do |line|
    parts = line.split(' | ')
    if parts[0] == movie_name
      case property
      when 'оценка'
        parts[1] = "Оценка: #{new_value}"
      when 'комментарий'
        parts[2] = "Комментарий: #{new_value}"
      when 'название'
        parts[0] = new_value
      end
    end
    parts.join(' | ')
  end
  
  File.open(DATA_FILE, 'w') { |file| file.puts(updated_data) }
end

def remove_movie(movie_name)
  data = []
  if File.exist?(DATA_FILE)
    data = File.readlines(DATA_FILE).map(&:chomp)
  end
  
  updated_data = data.reject { |line| line.start_with?(movie_name) }
  
  File.open(DATA_FILE, 'w') { |file| file.puts(updated_data) }
end

Telegram::Bot::Client.run(TOKEN) do |bot|
  bot.listen do |message|
    if message.is_a?(Telegram::Bot::Types::Message) && message.text&.start_with?('/')
      case message.text
      when '/help'
        help_message = <<~MESSAGE
        Список доступных команд:
        /start - начать общение с ботом
        /add_watched - добавить просмотренный фильм
        /list_movies - вывести список фильмов
        /remove_movie - удалить фильм из списка
        /edit_movie - редактировать информацию о фильме
        /help - вывести этот список команд
        MESSAGE
        bot.api.send_message(chat_id: message.chat.id, text: help_message)
      when '/start'
        bot.api.send_message(chat_id: message.chat.id, text: "Привет, #{message.from.first_name}! Я бот для учета фильмов, просмотренных с Кариной. Введи /help чтобы увидеть все мои команды!")
      when '/add_watched'
        bot.api.send_message(chat_id: message.chat.id, text: "Введите название фильма:")
        user_states[message.from.id] = { state: :waiting_for_movie_name }
      when '/list_movies'
        if File.exist?(DATA_FILE)
          movies_data = File.read(DATA_FILE)
          bot.api.send_message(chat_id: message.chat.id, text: "Список фильмов:\n#{movies_data}")
        else
          bot.api.send_message(chat_id: message.chat.id, text: "Список пуст.")
        end
      when '/remove_movie'
        bot.api.send_message(chat_id: message.chat.id, text: "Введите название фильма, который хотите удалить:")
        user_states[message.from.id] = { state: :waiting_for_movie_removal }
      when '/edit_movie'
        bot.api.send_message(chat_id: message.chat.id, text: "Введите название фильма, который хотите отредактировать:")
        user_states[message.from.id] = { state: :waiting_for_movie_edit }
      else
        bot.api.send_message(chat_id: message.chat.id, text: "Я не понимаю эту команду.")
      end
    else
      case user_states[message.from.id]&.fetch(:state, nil)
      when :waiting_for_movie_name
        movie_name = message.text
        user_states[message.from.id] = { state: :waiting_for_rating, movie_name: movie_name }
        bot.api.send_message(chat_id: message.chat.id, text: "Введите оценку для фильма '#{movie_name}':")
      when :waiting_for_rating
        rating = message.text
        user_states[message.from.id] = { state: :waiting_for_comment, movie_name: user_states[message.from.id][:movie_name], rating: rating }
        bot.api.send_message(chat_id: message.chat.id, text: "Введите комментарий для фильма '#{user_states[message.from.id][:movie_name]}':")
      when :waiting_for_comment
        comment = message.text
        movie_name = user_states[message.from.id][:movie_name]
        rating = user_states[message.from.id][:rating]
        
        File.open(DATA_FILE, 'a') { |file| file.puts "#{movie_name} | #{rating} | #{comment}" }
        bot.api.send_message(chat_id: message.chat.id, text: "Фильм '#{movie_name}' добавлен в список просмотренных.")
        
        user_states[message.from.id] = nil
      when :waiting_for_movie_removal
        movie_to_remove = message.text
        remove_movie(movie_to_remove)
        bot.api.send_message(chat_id: message.chat.id, text: "Фильм '#{movie_to_remove}' удален из списка просмотренных.")
        
        user_states[message.from.id] = nil
      when :waiting_for_movie_edit
        edit_movie_name = message.text
        user_states[message.from.id] = { state: :waiting_for_movie_edit_property, movie_name: edit_movie_name }
        bot.api.send_message(chat_id: message.chat.id, text: "Выберите свойство для редактирования (оценка, комментарий, название):")
      when :waiting_for_movie_edit_property
        property = message.text.downcase.strip
        if %w[оценка комментарий название].include?(property)
          user_states[message.from.id][:state] = :waiting_for_new_property_value
          user_states[message.from.id][:property] = property
          bot.api.send_message(chat_id: message.chat.id, text: "Введите новое значение для '#{property}':")
        else
          bot.api.send_message(chat_id: message.chat.id, text: "Неверное свойство. Пожалуйста, выберите оценка, комментарий или название.")
        end
      when :waiting_for_new_property_value
        new_value = message.text
        property = user_states[message.from.id][:property]
        edit_movie_name = user_states[message.from.id][:movie_name]
        
        update_movie_data(edit_movie_name, property, new_value)
        
        bot.api.send_message(chat_id: message.chat.id, text: "Информация о фильме '#{edit_movie_name}' обновлена: #{property.capitalize}: #{new_value}")
        
        user_states[message.from.id] = nil
      end
    end
  end
end
