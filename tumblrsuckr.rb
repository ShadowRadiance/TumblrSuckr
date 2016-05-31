#!/usr/bin/env ruby

require 'rubygems'
require 'optparse'
require 'json'
require 'net/http'
require 'fileutils'
require 'pp'

module TumblrSuckr

  class Application
    def initialize(argv)
      @params, @urls = parse_options(argv)
      @processor = TumblrSuckr::Processor.new(@params)
    end

    def run
      if @urls.empty?
        puts "Nothing to do." 
        puts "Usage: tumblrsuckr [-v] url-without-tumblr"
        puts "Example: tumblrsuckr -v staff (retrieves via staff.tumblr.com/archive)"
      else
        @urls.each do |url|
          @processor.process url
        end 
      end
    end

    def parse_options(argv)
      params = {}
      parser = OptionParser.new

      # parser.on("-n") { params[:line_numbering_style] ||= :all_lines }
      # parser.on("-b") { params[:line_numbering_style] = :significant_lines }
      # parser.on("-s") { params[:squeeze_extra_newlines] = true }
      parser.on("-v", "--[no-]verbose", "Run verbosely") { |v|
        params[:verbose] = v
      }
      
      params[:output_path] = "./tumblrsuckr/"
      parser.on("-o", "--output OUTPUT_PATH", "Output the files to OUTPUT_PATH") { |o| 
        params[:output_path] = o
      }
      urls = parser.parse(argv)

      [params, urls]
    end 
  end
  
  class Processor
    
    def initialize(params)
      @params = params
    end
    
    def parameterize(params)
      URI.escape(params.collect{|k,v| "#{k}=#{v}"}.join('&'))
    end
    
    def download_and_save(image_url, output_base)
      image_uri = URI.parse(image_url)
      output_path = image_uri.path
      output_path.gsub!('/', '-')
      output_path[0] = '/'
      server = image_uri.host
      # puts "Downloading #{image_uri.path} from #{server}"
      # DOWNLOAD AND SAVE FILE
      full_path = File.expand_path(output_base + output_path)
      puts "CREATING: #{output_base}#{output_path}"
      Net::HTTP.start(image_uri.host, image_uri.port) do |http|
        request = Net::HTTP::Get.new image_uri.request_uri
        http.request request do |response|
          open full_path, 'w' do |io|
            response.read_body do |chunk|
              io.write chunk
              print "."
            end
          end
        end
        puts
      end
    end
    
    def large_image_url_from_item(item)
      large_image_url = ''
      possible_sizes = [1280, 500, 400, 250, 100, 75]
      possible_sizes.each do |size|
        key = "photo-url-#{size}"
        if item.has_key? key
          return item[key]
        end
      end
    end
    
    def process(blogname)
      blog_url  = "http://#{blogname}.tumblr.com/api/read/json"
      params = {
        :type   => 'photo',
        :start  => 0,
        :num    => 0,
        :filter => 'text',
        :debug  => 1
      }
      
      puts "Pulling list from #{blog_url}"
      # create a list
      image_list = []

      # grab the info api
      params[:num] = 0
      uri = blog_url + "?" + parameterize(params)
      source = Net::HTTP.get(URI.parse(uri))
      content = JSON.parse(source)
      posts_start = content['posts-start']
      posts_total = content['posts-total']
      tumblelog   = content['tumblelog']
      
      puts "Reading: #{tumblelog['title']} (#{tumblelog['name']}.tumblr.com)"
      puts "Found #{posts_total} matching posts..."
      
      params[:start] = 0
      params[:num]   = 50
      
      while true
        tumblr_uri = blog_url + "?" + parameterize(params)
        source = Net::HTTP.get(URI.parse(tumblr_uri))
        content = JSON.parse(source)

        posts = content['posts']
        posts.each do |post|
          post_url = post['url']
          
          if post.has_key? 'photos'          
            photoset = post['photos']
            photoset.each do |photo|
              image_list << large_image_url_from_item(photo)
              # puts "\t#{post['id']}/#{photo['offset']}: #{large_image_url}"
            end
          else
            image_list << large_image_url_from_item(post)  
            # puts "\t#{post['id']}: #{large_image_url}"
          end
          
        end
        
        params[:start] += params[:num]
        if params[:start] >= posts_total
          break
        end
      end             
    
      if image_list.size > 1 
        image_list.sort!.uniq!
      end
      
      output_base = File.expand_path("#{@params[:output_path]}/#{tumblelog['name']}/")
      FileUtils.mkdir_p output_base
      
      puts "OUTPUTTING TO #{output_base}"
      
      image_list.each do |image_url|
        # each uri will be of the form http://nn.media.tumblr.com/path/filename
        #                           or http://nn.media.tumblr.com/filename
        # we will output to ./tumblrsuckr/tumblelog['name']/path/filename
        #                or ./tumblrsuckr/tumblelog['name']/filename respectively
        
        download_and_save image_url, output_base
      end  
      puts
      
    end
        
  end
  
end

############################# MAIN APPLICATION STARTER

begin
  TumblrSuckr::Application.new(ARGV).run
rescue Errno::ENOENT => err
  abort "TumblrSuckr: #{err.message}"
rescue OptionParser::InvalidOption => err
  abort "TumblrSuckr: #{err.message}\nusage: tumblrsuckr url"
end
