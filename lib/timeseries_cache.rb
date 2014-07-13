class TimeseriesCache
  class MissingValue < StandardError ; end
  class MissingOption < StandardError ; end

  TIMESTEP = 1.day

  attr_reader :key, :redis, :timestep, :ttl

  def initialize(options, &block)
    @key = options.fetch(:key) { raise MissingOption.new("missing option :key") }
    @redis = options.fetch(:redis, $redis)
    @timestep = options.fetch(:timestep, TIMESTEP)
    @ttl = options.fetch(:ttl, false)

    instance_eval &block if block_given?
  end

  def get(datetime)
    if set?(datetime)
      Marshal.load(redis.get(prefixed_key(datetime)))
    else
      raise MissingValue.new("missing #{key} at #{to_timestamp(datetime)}")
    end
  end

  def fetch(datetime, value = nil)
    begin
      get(datetime)
    rescue MissingValue
      set(datetime, block_given? ? yield(datetime) : value)
    end
  end

  def fetch_range(datetime_from, datetime_to, &block)
    (datetime_from..datetime_to).map do |datetime|
      fetch(datetime, &block)
    end
  end

  def set(datetime, value = nil)
    val = block_given? ? yield(datetime) : value
    redis.set(prefixed_key(datetime), Marshal.dump(val))
    set_ttl(datetime)
    val
  end

  def set?(datetime)
    redis.exists(prefixed_key(datetime))
  end

  private
  def set_ttl(datetime)
    redis.expire(prefixed_key(datetime), ttl) if ttl
  end

  def prefixed_key(datetime)
    [key, normalize_time(datetime)].join(':')
  end

  def normalize_time(datetime)
    timestamp = to_timestamp(datetime)
    timestamp - (timestamp % timestep)
  end

  def to_timestamp(datetime)
    case datetime.class
    when DateTime
      datetime.to_time.to_i
    when Time
      datetime.to_i
    when Date
      datetime.to_time.to_i
    when Integer
      datetime
    else
      DateTime.parse(datetime.to_s).to_time.to_i
    end
  end
end
