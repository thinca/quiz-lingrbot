# encoding: utf-8
require 'sinatra'
require 'json'
require 'yaml'
require 'hashie'
require 'open-uri'
require 'cgi'

class User
  attr_accessor :name, :point
end

class Score
end

class Quiz

  def initialize(json)
    @question_text = json['question']
    answers = json['answers'].zip(iterate(1, &:succ)).shuffle
    if answers.length == 2
      answers.sort!.reverse!  # o x
    else
      answers.shuffle!
    end
    @answer = answers.index{ |a, n| n == 1 } + 1  # 1 origin
    @answers = answers.map(&:first)
    @panelist = {}
    @nicknames = {}
  end

  def question(time)
    "問題: #{@question_text} (制限時間: #{time}秒)\n#{answer_list}"
  end

  def answer_list
    @answers.each_with_index.map{ |a, i| "#{(i + 1)}. #{a}" }.join("\n")
  end

  def panelist
    rights = @panelist.select{ |user, answer| answer == @answer }.keys.map{ |user| "#{@nicknames[user]} さん" }
    return '正解者はいませんでした。' if rights.empty?
    "正解者は #{rights.join('、')}。おめでとうございます。"
  end

  def answer(user, nick, answer)
    return unless answer =~ /^\d+$/
    answer = answer.to_i
    return unless (1..@answers.length).include? answer
    @panelist[user] = answer
    @nicknames[user] = nick
  end

  def check
    "正解は #{@answer}. #{@answers[@answer - 1]} でした。\n#{panelist}"
  end
end

def iterate(init, &block)
  Enumerator.new do |y|
    loop do
      y << init
      init = block.call(init)
    end
  end
end

def quiz_from_all
  JSON.parse(open("http://api.quizken.jp/api/quiz-index/api_key/ma7/count/1").read).first
end

def quiz_from_genre(genre)
  JSON.parse(open("http://api.quizken.jp/api/quiz-index/api_key/ma7/genre_name/#{genre}/count/1").read).first
end

def quiz_from_phrase(phrase)
  JSON.parse(open("http://api.quizken.jp/api/quiz-search/api_key/ma7/phrase/#{CGI.escape(phrase)}/count/50").read).sample
end

def say(room, text)
  open("http://lingr.com/api/room/say?room=#{room}&bot=#{$config.bot_name}&text=#{CGI.escape(text)}&bot_verifier=#{$config.bot_verifier}")
end

$config = Hashie::Mash.new(YAML.load(ARGF))

quiz = {}
t = nil

get '/' do
  "quiz bot for lingr.\nPowered by http://quizken.jp/api/ma7"
end

post '/' do
  content_type :text
  request_data = JSON.parse(request.body.read)
  request_data['events'].select{ |e| e['message'] }.map do |e|
    m = e['message']
    text = m['text']
    room = m['room']
    if text =~ /^#quiz/
      return '現在出題中です。' if quiz[room]

      phrase = text[/^#quiz\s*(.+)/, 1]
      quiz_data = phrase ? quiz_from_phrase(phrase) : quiz_from_all
      return '問題が見付かりませんでした。' unless quiz_data
      return '現在出題中です。' if quiz[room]
      quiz[room] = Quiz.new(quiz_data)
      time = 30
      Thread.new do
        half = time / 2
        sleep time - half
        say(room, "#残り#{half}秒")
        sleep half
        result = quiz[room].check
        say(room, result)
        quiz.delete(room)
      end
      return quiz[room].question(time)
    elsif quiz[room]
      quiz[room].answer(m['speaker_id'], m['nickname'], text)
      return ''
    end
  end
  ''
end
