require 'open-uri'
require 'jbuilder'
Bundler.require

$redis = Redis::Namespace.new(:SlideMix, redis: Redis::Pool.new(url: ENV['REDISTOGO_URL'] || 'redis://localhost:6379/15'))

class Slide
	URL_REGEXP = %r{^http://www\.slideshare\.net/(?<user_id>.+)/.+/(?<page>.+)$}
	include Mongoid::Document
	include Mongoid::Timestamps
	field :title, type: String
	field :urls_text, type: String
	validates :title, :length => {:maximum => 100}, :presence => true
	validate do |slide|
		urls = urls_text.split(/\r?\n/)
		urls.each do |url|
			unless url.match(URL_REGEXP)
				slide.errors.add(:urls_text, 'include invalid URL(s)')
				break
			end
		end
		if urls.size > 50
			slide.errors.add(:urls_text, 'includes more than 50 URLs')
		end

	end
	def urls
		self.urls_text.split(/\r?\n/)
	end
end

configure do
	ENDPOINT = "http://www.slideshare.net/slideshow/embed_code/"
	TITLE = 'SLIDE MIX'
	CACHE_LIFE = 60*60*24

	Mongoid.load!('./mongoid.yml')

	set :haml, escape_attrs: false, ugly: true, escape_html: true
end

helpers do
	def cache(key)
		unless value = redis.get(key)
			value = yield
			redis.set(key, value)
			redis.expire(key, CACHE_LIFE)
		end
		value
	end

	def redis
		$redis
	end

	def title
		@slide ? @slide.title + " - #{TITLE}" : TITLE
	end

	def random_image
		%w(
			https://farm7.staticflickr.com/6085/6037735595_993ee88d33.jpg
			https://farm7.staticflickr.com/6074/6038283286_50493e35eb.jpg
			https://farm7.staticflickr.com/6135/6037734315_df5e749df8.jpg
			https://farm5.staticflickr.com/4143/4868208063_f4f94687c6.jpg
			https://farm5.staticflickr.com/4100/4868208431_8714904dbc.jpg
			https://farm5.staticflickr.com/4141/4868207321_6055468dd5.jpg
			https://farm5.staticflickr.com/4141/4868820180_e3b7e7e966.jpg
			https://farm5.staticflickr.com/4137/4868205919_2690a6b71f.jpg
			https://farm5.staticflickr.com/4073/4868818794_abb2de8401.jpg
			https://farm5.staticflickr.com/4139/4868205175_4a351615bf.jpg
			https://farm5.staticflickr.com/4096/4868818154_c338fef95c.jpg
			https://farm5.staticflickr.com/4120/4868817244_8300fdb836.jpg
			https://farm3.staticflickr.com/2455/3781308710_947231d497.jpg
			https://farm3.staticflickr.com/2585/3780498525_7059ece143.jpg
			https://farm3.staticflickr.com/2665/3779276981_156ec9ef94.jpg
			https://farm4.staticflickr.com/3197/2324133651_89679385ed.jpg
			https://farm4.staticflickr.com/3273/2324132813_413605b956.jpg
			https://farm3.staticflickr.com/2403/2324130955_28e1598c77.jpg
			https://farm8.staticflickr.com/7203/6982348373_19da9bdab1.jpg
			https://farm8.staticflickr.com/7050/6982349247_b6c7dfa40b.jpg
		).sample
	end
end

get %r{/oembed(.(json|xml)|/)?} do
	halt 400 if params[:url].nil? || (match = params[:url].match(Slide::URL_REGEXP)).nil?
	format = params[:format] || params[:captures][2] || 'json'
	user_id, page = match[:user_id], match[:page]
	html = cache(params[:url]) { open(params[:url]).read }
	doc = Nokogiri::HTML(html, nil, 'utf-8')
	block = lambda do |format|
		format.type 'rich'
		format.version '1.0'
		format.author_name html[/"user_name":"([^\"]+?)"/, 1]
		format.author_url "http://www.slideshare.net/#{user_id}"
		format.provider_name 'SlideShare'
		format.provider_url 'http://www.slideshare.net'
		format.url doc.css("div.slide[data-index='#{page}'] img").first['data-normal']
		format.width 638
		format.height 442
		format.title doc.css('title').first.text
		format.description doc.css("meta[name='description']").first['content']
	end
	case format
	when 'json'
		content_type 'text/json'
		Jbuilder.encode {|json| block.call(json) }
	when 'xml'
		content_type 'application/xml'
		builder(layout: false) {|xml| xml.instruct!; xml.oembed { block.call(xml) }}
	else
		halt 400
	end
end

get '/:id/e' do
	@slide = Slide.find(params[:id]) if params[:id] != '*'
	haml :'/:id/e'
end

get '/:id' do
	@slide = Slide.find(params[:id])
	haml :'/:id'
end

post '/:id' do
	if params[:id] == '*'
		@slide = Slide.create params.slice('title', 'urls_text')
	else
		@slide = Slide.find(params[:id])
		@slide.update_attributes params.slice('title', 'urls_text')
	end
	if @slide.save
		redirect "/#{@slide.id}"
	else
		haml :'/:id/e'
	end
end

get '/' do
	haml :'/'
end

__END__
@@ layout
!!! 5
%html
	%head
		%meta{charset: 'utf-8'}/
		%meta{name:"viewport",content:"width=device-width,initial-scale=1.0"}
		%title= title
		%script{src:"http://ajax.googleapis.com/ajax/libs/jquery/1.8.3/jquery.min.js",type:"text/javascript"}
		%script{src:"//cdnjs.cloudflare.com/ajax/libs/underscore.js/1.5.2/underscore-min.js",type:"text/javascript"}
		%script{src:"/reveal.min.js",type:"text/javascript"}
		%link{rel:'stylesheet',href:'/reveal.min.css'}
		%link{rel:'stylesheet',href:'/default.css'}
		%link{rel:'stylesheet',href:'http://maxcdn.bootstrapcdn.com/bootstrap/3.2.0/css/bootstrap.min.css'}
		:css
			a,a:hover { color: #13daec; }
			section.top { color: white; -webkit-text-stroke: 2px black }
			p.caption { font-size: small }
	%body
		%div.reveal
			%div.slides
				!= yield
		:coffeescript
			Reveal.initialize
				controls: true
				progress: true
				slideNumber: true
				history: true
				hideAddressBar: true
@@ /:id/e
%section.top{'data-background'=>random_image}
	- if @slide && !@slide.errors.empty?
		.alert.alert-danger
			%ul
				- @slide.errors.each do |field, message|
					%li= "#{field} #{message}"
	%form.form{role:'form',method:'POST',action:params[:id] ? "/#{params[:id]}" : "/*"}
		%div.form-group
			%label.control-label{for:'title'} TITLE
			%input.form-control{name:'title',type:'text',value:@slide.try(:title)}
		%div.form-group
			%label.control-label{for:'urls_text'} URL LIST
			%textarea.form-control{name:'urls_text',rows:'10'}
				= @slide ? @slide.urls_text : 'http://www.slideshare.net/esminc/ss-3015720/11'
		%div.form-group
			%button.btn.btn-default= @slide ? 'UPDATE' : 'CREATE'
	%a{href:@slide ? "/#{@slide.id}": '#/'} BACK
@@ /:id
%section
	%h1= @slide.title
	%p
		%a{href:"/"} BACK
		&nbsp;|&nbsp;
		%a{href:"#{@slide.id}/e"} EDIT SLIDE
- @slide.urls.each do |url|
	%section{'data-url'=>url,'data-url-loaded'=>'false'} loading ...
%script{id:'template',type:'text/template'}
	%p.caption
		%a{href:'<%= meta.provider_url %>',target:'_blank'}
			%img{src:'http://www.slideshare.net/favicon.ico'}
		%a{href:'<%= url %>',target:'_blank'} <%= meta.title %> (p<%= url.match(/\/(\d+)$/)[1] %>)
		%br
		%a{href:'<%= meta.author_url %>',target:'_blank'} <%= meta.author_name %>
	%p
		%img{src:'<%= meta.url %>'}
:coffeescript
	template = $('#template').text()
	loadUrl = (e)->
		sections = $('div.slides section').slice(e.indexh - 1, e.indexh + 2)
		sections.each (i, section)->
			url = $(section).attr('data-url')
			urlLoaded = $(section).attr('data-url-loaded')
			if url && urlLoaded == 'false'
				$(section).attr('data-url-loaded', 'true')
				$.get('/oembed.json', {url: url})
				.done (meta)->
					$(section).html(_.template(template, {url: url, meta: meta}))
					Reveal.layout()
	Reveal.addEventListener('slidechanged', loadUrl)
	Reveal.addEventListener('ready', loadUrl)
	Reveal.layout()
@@ /
%section.top
	%section{'data-background'=>random_image}
		%h1{style:'color:white'} SLIDE MIX
		%p
			%a{href:'#/0/2'} CREATE SLIDE
	%section{'data-background'=>random_image}
		%h2 SLIDES
		%ul
			- Slide.desc(:created_at).limit(10).each do |slide|
				%li
					%a{href:"/#{slide.id}"}= slide.title
	!= haml :'/:id/e'
%section.top{'data-background'=>random_image}
	%h2 ABOUT
	%ul
		%li create new slide with exsitent slideshare slides
		%li contact @tily if any problem
