#!/usr/bin/ruby
require 'tempfile'

Heuristics = ["rand_rand","rand_mf","next_rand","next_mf","moms","dlis"]
Algos = ["wl","dpll"]
Db_store = "data.db"
Skeleton = "skel.p"
Threads = 2

class Result
  attr_accessor :timers, :stats, :sat

  def initialize
    @timers = {}
    @stats = {}
    @sat = nil
  end

  def is_compatible? r
    raise ArgumentError unless r == nil or r.is_a? Result
    r == nil or (@timers.keys.sort == r.timers.keys.sort and @stats.keys.sort == r.stats.keys.sort)
  end 

  def add r
    raise ArgumentError unless r == nil or r.is_a? Result
    if r then
      @timers.keys.each { |key| @timers[key] += r.timers[key] }
      @stats.keys.each { |key| @stats[key] += r.stats[key] }
      @sat += r.sat
    end
    self
  end
end

class Report
  attr_reader :count, :result
  
  def initialize
    @count = 0
    @result = nil
  end

  def << result
    raise ArgumentError unless result.is_compatible? @result
    @result = result.add @result
    @count += 1
    self
  end

  def merge! report
    raise ArgumentError unless report.is_a? Report
    @count += report.count - 1
    self << report.result
  end
end


class Database
  attr :data

  def initialize (source = nil)
    @data = {}
    @data.default = nil
    @mutex = Mutex::new
    raise ArgumentError if source and not source.is_a? IO
    if source
      merge! Marshal.load(source)
    end
  end

  def save
    Marshal.dump(self)
  end

  def record problem, report
    @mutex.lock
    repr = @data[@data.keys[0]]
    if @data.key? problem then
      @data[problem].merge! report
    else
      @data[problem] = report
    end
    @mutex.unlock
  end

  def merge! o
    raise ArgumentError unless o.is_a? Database
    o.data.each { |problem,report| self.record problem,report }
    self
  end
end

class Problem

  attr_reader :n, :l, :k, :algo, :heuristic

  def initialize(n = 10, l = 3, k = 10, algo = "dpll", heuristic = "rand_rand")
    @temp = nil
    @n = n
    @l = l
    @k = k
    @algo = if Algos.include? algo
              algo 
            else
              raise ArgumentError 
            end
    @heuristic = if Heuristics.include? heuristic 
                   heuristic
                 else
                   raise ArgumentError
                 end
  end
  
  def to_s
    "<Problem : n=#{@n}, l=#{@l}, k=#{@k}, algo=#{@algo}, heuristic=#{@heuristic}>"
  end

  alias inspect to_s
  
  def hash
    to_s.hash
  end
  
  def eql? o
    to_s.eql? o.to_s
  end
  
  def gen
    temp = Tempfile.open("sat")
    system "./gen #{@n} #{@l} #{@k} > #{temp.path}"
    Proc::new {
      result = Result::new
      #puts "./main -algo #{@algo} -h #{@heuristic} #{temp.path} 2>&1"
      IO::popen "./main -algo #{@algo} -h #{@heuristic} #{temp.path} 2>&1" do |io|
        io.each do |line|
          case line
          when /\[stats\] (?<stat>\w+) = (?<value>\d+)/
            result.stats[$~[:stat]] = $~[:value].to_i
          when /\[timer\] (?<timer>\w+) : (?<value>\d+(\.\d+)?) s/
            result.timers[$~[:timer]] = $~[:value].to_f
          when /s SATISFIABLE/
            result.sat = 1.0
          when /s UNSATISFIABLE/
            result.sat = 0.0
          end
        end
      end
      result
    }
  end
end


def run_tests(n,l,k,algos,heuristics,sample=1,&block)
  n.each do |n_|
    l.each do |l_|
      k.each do |k_|
        algos.each do |a_|
          heuristics.each do |h_|
            report = Report::new
            p = Problem::new(n_,l_,k_,a_,h_)
            sample.times do || 
                report << p.gen.call
            end
            yield p, report
          end
        end
      end
    end
  end
  true
end

def select_data(n,l,k,&block)
  lambda { |p|
    if (n==nil or n===p.n) and (l==nil or l===p.l) and (k==nil or k===p.k)
      yield p
    end
  }
end

class Gnuplot
  attr :script_file
  def initialize title, columns, data
    

def main
  puts "Hello World"
  db = Database::new
  algos = ["dpll","wl"]
  h = ["rand_rand","rand_mf"]
  n = (1..5).map {|x| 10*x}
  l = [3]
  k = (1..5).map {|x| 10*x}
  sample = 5
  Threads.times do 
    Thread::new do
      run_tests(n,l,k,algos,h,sample) { |problem, report| db.record(problem, report) }  
    end
  end
  db
end

if __FILE__ == $0
  main
end