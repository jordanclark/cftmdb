component {
	// cfprocessingdirective( preserveCase=true );

	TMDb function init(
		required string apiKey
	,	required string apiReadKey
	,	string apiUrl= "https://api.themoviedb.org/<ver>"
	,	string apiVersion= 3
	,	string defaultLanguage= "en-US"
	,	numeric throttle= 250
	,	numeric httpTimeOut= 60
	,	boolean debug
	) {
		arguments.debug = ( arguments.debug ?: request.debug ?: false );
		this.apiKey= arguments.apiKey;
		this.apiReadKey= arguments.apiReadKey;
		this.apiUrl= arguments.apiUrl;
		this.apiVersion= arguments.apiVersion;
		this.defaultLanguage= arguments.defaultLanguage;
		this.httpTimeOut= arguments.httpTimeOut;
		this.throttle= arguments.throttle;
		this.debug= arguments.debug;
		this.lastRequest= server.tmdb_lastRequest ?: 0;
		this.config= {};
		this.backdropSizes= ["w300","w780","w1280","original"];
		this.logoSizes= ["w45","w92","w154","w185","w300","w500","original"];
		this.posterSizes= ["w92","w154","w185","w342","w500","w780","original"];
		this.profileSizes= ["w45","w185","h632","original"];
		this.stillSizes= ["w92","w185","w300","original"];
		this.imageUrl= "https://image.tmdb.org/t/p/";
		return this;
	}

	string function getImageUrl( required string size, required string key ) {
		return this.imageUrl & arguments.size & arguments.key;
	}

	function debugLog( required input ) {
		if ( structKeyExists( request, "log" ) && isCustomFunction( request.log ) ) {
			if ( isSimpleValue( arguments.input ) ) {
				request.log( "TMDb: " & arguments.input );
			} else {
				request.log( "TMDb: (complex type)" );
				request.log( arguments.input );
			}
		} else if ( this.debug ) {
			var info= ( isSimpleValue( arguments.input ) ? arguments.input : serializeJson( arguments.input ) );
			cftrace(
				var= "info"
			,	category= "TMDb"
			,	type= "information"
			);
		}
		return;
	}

	struct function apiRequest( required string api ) {
		arguments[ "api_key" ]= this.apiKey;
		var http= {};
		var item= "";
		var out= {
			args= arguments
		,	success= false
		,	error= ""
		,	status= ""
		,	statusCode= 0
		,	response= ""
		,	verb= listFirst( arguments.api, " " )
		,	requestUrl= ""
		,	data= {}
		,	delay= 0
		};
		out.requestUrl &= listRest( out.args.api, " " );
		structDelete( out.args, "api" );
		// replace {var} in url 
		for ( item in out.args ) {
			// strip NULL values 
			if ( isNull( out.args[ item ] ) ) {
				structDelete( out.args, item );
			} else if ( isSimpleValue( arguments[ item ] ) && arguments[ item ] == "null" ) {
				arguments[ item ]= javaCast( "null", 0 );
			} else if ( findNoCase( "{#item#}", out.requestUrl ) ) {
				out.requestUrl= replaceNoCase( out.requestUrl, "{#item#}", out.args[ item ], "all" );
				structDelete( out.args, item );
			}
		}
		if ( out.verb == "GET" ) {
			out.requestUrl &= this.structToQueryString( out.args, true );
		} else if ( !structIsEmpty( out.args ) ) {
			out.body= serializeJSON( out.args );
		}
		out.requestUrl= replace( this.apiUrl, "<ver>", this.apiVersion ) & out.requestUrl;
		this.debugLog( "API: #uCase( out.verb )#: #out.requestUrl#" );
		if ( structKeyExists( out, "body" ) ) {
			this.debugLog( out.body );
		}
		// this.debugLog( out );
		// throttle requests by sleeping the thread to prevent overloading api
		if ( this.lastRequest > 0 && this.throttle > 0 ) {
			out.delay= this.throttle - ( getTickCount() - this.lastRequest );
			if ( out.delay > 0 ) {
				this.debugLog( "Pausing for #out.delay#/ms" );
				sleep( out.delay );
			}
		}
		cftimer( type="debug", label="tmdb request" ) {
			cfhttp( charset="UTF-8", throwOnError=false, url=out.requestUrl, timeOut=this.httpTimeOut, result="http", method=out.verb ) {
				if ( out.verb == "POST" || out.verb == "PUT" || out.verb == "PATCH" ) {
					cfhttpparam( name="content-type", type="header", value="application/json" );
				}
				if ( structKeyExists( out, "body" ) ) {
					cfhttpparam( type="body", value=out.body );
				}
			}
			if ( this.throttle > 0 ) {
				this.lastRequest= getTickCount();
				server.tmdb_lastRequest= this.lastRequest;
			}
		}
		out.response= toString( http.fileContent );
		// this.debugLog( out.response );
		out.statusCode= http.responseHeader.Status_Code ?: 500;
		if ( left( out.statusCode, 1 ) == 4 || left( out.statusCode, 1 ) == 5 ) {
			out.error= "status code error: #out.statusCode#";
		} else if ( out.response == "Connection Timeout" || out.response == "Connection Failure" ) {
			out.error= out.response;
		} else if ( left( out.statusCode, 1 ) == 2 ) {
			out.success= true;
		}
		// parse response 
		try {
			out.data= deserializeJSON( out.response );
			if ( isStruct( out.data ) && structKeyExists( out.data, "error" ) ) {
				out.success= false;
				out.error= out.data.error;
			} else if ( isStruct( out.data ) && structKeyExists( out.data, "status" ) && out.data.status == 400 ) {
				out.success= false;
				out.error= out.data.detail;
			}
		} catch (any cfcatch) {
			out.error= "JSON Error: " & (cfcatch.message?:"No catch message") & " " & (cfcatch.detail?:"No catch detail");
		}
		if ( len( out.error ) ) {
			out.success= false;
		}
		this.debugLog( out.statusCode & " " & out.error );
		return out;
	}

	// ---------------------------------------------------------------------------------------- 
	// DISCOVER MOVIES 
	// ---------------------------------------------------------------------------------------- 

	struct function discoverMovies(
		string language= this.defaultLanguage
	,	string sort_by= "popularity.desc"
	,	string certification_country
	,	string certification
	,	string certification_lte
	,	boolean include_adult
	,	boolean include_video
	,	numeric page= 1
	,	numeric primary_release_year
	,	string primary_release_date_gte
	,	string primary_release_date_lte
	,	string release_date_gte
	,	string release_date_lte
	,	string vote_count_gte
	,	string vote_count_lte
	,	string vote_average_gte
	,	string vote_average_lte
	,	string with_cast
	,	string with_crew
	,	string with_companies
	,	string with_genres
	,	string with_keywords
	,	string with_people
	,	numeric year
	,	string without_genres
	,	string without_keywords
	,	string with_runtime_gte
	,	string with_runtime_lte
	,	numeric with_release_type
	,	string with_original_language
	) {
		// rename stupid .lte and .gte arguments 
		var item= "";
		for ( item in arguments ) {
			if ( right( item, 3 ) == "lte" || right( item, 3 ) == "gte" ) {
				arguments[ replaceList( item, "_lte,_gte", ".lte,.gte" ) ]= arguments[ item ];
				structDelete( arguments, item );
			}
		}
		return this.apiRequest( api= "GET /discover/movie", argumentCollection= arguments );
	}

	struct function discoverTV(
		string language= this.defaultLanguage
	,	string sort_by= "popularity.desc"
	,	string air_date_gte
	,	string air_date_lte
	,	string first_air_date_gte
	,	string first_air_date_lte
	,	numeric first_air_date_year
	,	numeric page= 1
	,	string timezone
	,	string vote_average_gte
	,	string vote_count_gte
	,	string with_genres
	,	string with_networks
	,	string without_genres
	,	string with_runtime_gte
	,	string with_runtime_lte
	,	boolean include_null_first_air_dates
	,	string with_original_language
	,	string without_keywords
	) {
		// rename stupid .lte and .gte arguments 
		var item= "";
		for ( item in arguments ) {
			if ( right( item, 3 ) == "lte" || right( item, 3 ) == "gte" ) {
				arguments[ replaceList( item, "_lte,_gte", ".lte,.gte" ) ]= arguments[ item ];
				structDelete( arguments, item );
			}
		}
		return this.apiRequest( api= "GET /discover/tv", argumentCollection= arguments );
	}

	// ---------------------------------------------------------------------------------------- 
	// FIND ID METHODS 
	// ---------------------------------------------------------------------------------------- 

	struct function findByID( required string external_id, string language= this.defaultLanguage, required string external_source ) {
		return this.apiRequest( api= "GET /find/{external_id}", argumentCollection= arguments );
	}

	struct function findByTVdbID( required string imdb_id, string language= this.defaultLanguage ) {
		arguments[ "external_source" ]= "tvdb_id";
		arguments.external_id= arguments.tvdb_id;
		structDelete( arguments, "tvdb_id" );
		return this.apiRequest( api= "GET /find/{external_id}", argumentCollection= arguments );
	}

	struct function findByIMDbID( required string imdb_id, string language= this.defaultLanguage ) {
		if ( isNumeric( arguments.imdb_id ) ) {
			arguments.imdb_id= this.imdbID( arguments.imdb_id );
		}
		arguments.external_source= "imdb_id";
		arguments.external_id= arguments.imdb_id;
		structDelete( arguments, "imdb_id" );
		return this.apiRequest( api= "GET /find/{external_id}", argumentCollection= arguments );
	}

	// ---------------------------------------------------------------------------------------- 
	// SEARCH METHODS 
	// ---------------------------------------------------------------------------------------- 

	struct function searchMovies(
		required string query
	,	numeric page= 1
	,	string language= this.defaultLanguage
	,	boolean include_adult
	,	string region
	,	numeric year
	,	numeric primary_release_year
	) {
		if ( structKeyExists( arguments, "region" ) ) {
			arguments.region= uCase( arguments.region );
		}
		return this.apiRequest( api= "GET /search/movie", argumentCollection= arguments );
	}

	struct function searchTvShows(
		required string query
	,	numeric page= 1
	,	string language= this.defaultLanguage
	,	numeric first_air_date_year
	) {
		return this.apiRequest( api= "GET /search/tv", argumentCollection= arguments );
	}

	struct function searchPeople(
		required string query
	,	numeric page= 1
	,	string language= this.defaultLanguage
	,	boolean include_adult
	,	string region
	) {
		if ( structKeyExists( arguments, "region" ) ) {
			arguments.region= uCase( arguments.region );
		}
		return this.apiRequest( api= "GET /search/person", argumentCollection= arguments );
	}

	struct function searchCompany( required string query, numeric page= 1 ) {
		return this.apiRequest( api= "GET /search/company", argumentCollection= arguments );
	}

	struct function searchKeywords( required string query, numeric page= 1 ) {
		return this.apiRequest( api= "GET /search/keyword", argumentCollection= arguments );
	}

	struct function searchCollections( required string query, numeric page= 1, string language= this.defaultLanguage ) {
		return this.apiRequest( api= "GET /search/collection", argumentCollection= arguments );
	}

	struct function searchMulti(
		required string query
	,	numeric page= 1
	,	string language= this.defaultLanguage
	,	boolean include_adult
	,	string region
	) {
		if ( structKeyExists( arguments, "region" ) ) {
			arguments.region= uCase( arguments.region );
		}
		return this.apiRequest( api= "GET /search/multi", argumentCollection= arguments );
	}

	// ---------------------------------------------------------------------------------------- 
	// MOVIE METHODS 
	// ---------------------------------------------------------------------------------------- 

	struct function getMovie( required string movie_id, string language= this.defaultLanguage, string append_to_response ) {
		return this.apiRequest( api= "GET /movie/{movie_id}", argumentCollection= arguments );
	}

	struct function getMovieTitles( required string movie_id, required string country ) {
		return this.apiRequest( api= "GET /movie/{movie_id}/alternative_titles", argumentCollection= arguments );
	}

	struct function getMovieCredits( required string movie_id ) {
		return this.apiRequest( api= "GET /movie/{movie_id}/credits", argumentCollection= arguments );
	}

	struct function getMovieExternalIDs( required string movie_id ) {
		return this.apiRequest( api= "GET /movie/{movie_id}/external_ids", argumentCollection= arguments );
	}

	struct function getMovieImages( required string movie_id, string language= this.defaultLanguage, string include_image_language= "en,null" ) {
		return this.apiRequest( api= "GET /movie/{movie_id}/images", argumentCollection= arguments );
	}

	struct function getMovieKeywords( required string movie_id ) {
		return this.apiRequest( api= "GET /movie/{movie_id}/keywords", argumentCollection= arguments );
	}

	struct function getMovieReleaseDates( required string movie_id ) {
		return this.apiRequest( api= "GET /movie/{movie_id}/release_dates", argumentCollection= arguments );
	}

	struct function getMovieVideos( required string movie_id, string language= this.defaultLanguage ) {
		return this.apiRequest( api= "GET /movie/{movie_id}/videos", argumentCollection= arguments );
	}

	struct function getMovieTranslations( required string movie_id ) {
		return this.apiRequest( api= "GET /movie/{movie_id}/translations", argumentCollection= arguments );
	}

	struct function getMovieRecommendations( required string movie_id, string language= this.defaultLanguage, numeric page= 1 ) {
		return this.apiRequest( api= "GET /movie/{movie_id}/recommendations", argumentCollection= arguments );
	}

	struct function getMovieSimilar( required string movie_id, string language= this.defaultLanguage, numeric page= 1 ) {
		return this.apiRequest( api= "GET /movie/{movie_id}/similar", argumentCollection= arguments );
	}

	struct function getMovieReviews( required string movie_id, string language= this.defaultLanguage, numeric page= 1 ) {
		return this.apiRequest( api= "GET /movie/{movie_id}/reviews", argumentCollection= arguments );
	}

	struct function getMovieLists( required string movie_id, string language= this.defaultLanguage, numeric page= 1 ) {
		return this.apiRequest( api= "GET /movie/{movie_id}/lists", argumentCollection= arguments );
	}

	struct function getMoviesPopular( string language= this.defaultLanguage, numeric page= 1, string region ) {
		if ( structKeyExists( arguments, "region" ) ) {
			arguments.region= uCase( arguments.region );
		}
		return this.apiRequest( api= "GET /movie/popular", argumentCollection= arguments );
	}

	struct function getMoviesTopRated( string language= this.defaultLanguage, numeric page= 1, string region ) {
		if ( structKeyExists( arguments, "region" ) ) {
			arguments.region= uCase( arguments.region );
		}
		return this.apiRequest( api= "GET /movie/top_rated", argumentCollection= arguments );
	}

	struct function getMovieTopRated( string language= this.defaultLanguage, numeric page= 1, string region ) {
		if ( structKeyExists( arguments, "region" ) ) {
			arguments.region= uCase( arguments.region );
		}
		return this.apiRequest( api= "GET /movie/top_rated", argumentCollection= arguments );
	}

	struct function getMovieGenres( string language= this.defaultLanguage ) {
		return this.apiRequest( api= "GET /genre/movie/list", argumentCollection= arguments );
	}

	struct function getMovieCertifications() {
		return this.apiRequest( api= "GET /certification/movie/list", argumentCollection= arguments );
	}

	struct function getMovieChanges( numeric page= 1, string start_date, string end_date ) {
		return this.apiRequest( api= "GET /movie/changes", argumentCollection= arguments );
	}

	// ---------------------------------------------------------------------------------------- 
	// TV METHODS 
	// ---------------------------------------------------------------------------------------- 

	struct function getTV( required string tv_id, string language= this.defaultLanguage, string append_to_response ) {
		return this.apiRequest( api= "GET /tv/{tv_id}", argumentCollection= arguments );
	}

	struct function getTVTitles( required string tv_id, required string country ) {
		return this.apiRequest( api= "GET /tv/{tv_id}/alternative_titles", argumentCollection= arguments );
	}

	struct function getTVContentRatings( required string tv_id, string language= this.defaultLanguage ) {
		return this.apiRequest( api= "GET /tv/{tv_id}/content_ratings", argumentCollection= arguments );
	}

	struct function getTVCredits( required string tv_id ) {
		return this.apiRequest( api= "GET /tv/{tv_id}/credits", argumentCollection= arguments );
	}

	struct function getTVExternalIDs( required string tv_id ) {
		return this.apiRequest( api= "GET /tv/{tv_id}/external_ids", argumentCollection= arguments );
	}

	struct function getTVImages( required string tv_id, string language= this.defaultLanguage, string include_image_language= "en,null" ) {
		return this.apiRequest( api= "GET /tv/{tv_id}/images", argumentCollection= arguments );
	}

	struct function getTVKeywords( required string tv_id ) {
		return this.apiRequest( api= "GET /tv/{tv_id}/keywords", argumentCollection= arguments );
	}

	struct function getTVRecommendations( required string tv_id, string language= this.defaultLanguage, numeric page= 1 ) {
		return this.apiRequest( api= "GET /tv/{tv_id}/recommendations", argumentCollection= arguments );
	}

	struct function getTVSimilar( required string tv_id, string language= this.defaultLanguage, numeric page= 1 ) {
		return this.apiRequest( api= "GET /tv/{tv_id}/similar", argumentCollection= arguments );
	}

	struct function getTVTranslations( required string tv_id ) {
		return this.apiRequest( api= "GET /tv/{tv_id}/translations", argumentCollection= arguments );
	}

	struct function getTVVideos( required string tv_id, string language= this.defaultLanguage ) {
		return this.apiRequest( api= "GET /tv/{tv_id}/release_dates", argumentCollection= arguments );
	}

	struct function getTVsPopular( string language= this.defaultLanguage, numeric page= 1, string region ) {
		if ( structKeyExists( arguments, "region" ) ) {
			arguments.region= uCase( arguments.region );
		}
		return this.apiRequest( api= "GET /tv/popular", argumentCollection= arguments );
	}

	struct function getTVsTopRated( string language= this.defaultLanguage, numeric page= 1, string region ) {
		if ( structKeyExists( arguments, "region" ) ) {
			arguments.region= uCase( arguments.region );
		}
		return this.apiRequest( api= "GET /tv/top_rated", argumentCollection= arguments );
	}

	struct function getTVGenres( string language= this.defaultLanguage ) {
		return this.apiRequest( api= "GET /genre/tv/list", argumentCollection= arguments );
	}

	struct function getTVCertifications() {
		return this.apiRequest( api= "GET /certification/tv/list", argumentCollection= arguments );
	}

	struct function getTVChanges( numeric page= 1, string start_date, string end_date ) {
		return this.apiRequest( api= "GET /tv/changes", argumentCollection= arguments );
	}

	// ---------------------------------------------------------------------------------------- 
	// PEOPLE METHODS 
	// ---------------------------------------------------------------------------------------- 

	struct function getPerson( required string person_id, string language= this.defaultLanguage, string append_to_response ) {
		return this.apiRequest( api= "GET /person/{person_id}", argumentCollection= arguments );
	}

	struct function getPersonMovieCredits( required string person_id, string language= this.defaultLanguage ) {
		return this.apiRequest( api= "GET /person/{person_id}/movie_credits", argumentCollection= arguments );
	}

	struct function getPersonTVCredits( required string person_id, string language= this.defaultLanguage ) {
		return this.apiRequest( api= "GET /person/{person_id}/tv_credits", argumentCollection= arguments );
	}

	struct function getPersonCredits( required string person_id, string language= this.defaultLanguage ) {
		return this.apiRequest( api= "GET /person/{person_id}/combined_credits", argumentCollection= arguments );
	}

	struct function getPersonImages( required string person_id ) {
		return this.apiRequest( api= "GET /person/{person_id}/images", argumentCollection= arguments );
	}

	struct function getPersonTaggedImages( required string person_id, numeric page= 1, string language= this.defaultLanguage ) {
		return this.apiRequest( api= "GET /person/{person_id}/tagged_images", argumentCollection= arguments );
	}

	struct function getPersonExternalIDs( required string person_id ) {
		return this.apiRequest( api= "GET /person/{person_id}/external_ids", argumentCollection= arguments );
	}

	struct function getPersonChanges( numeric page= 1, string start_date, string end_date ) {
		return this.apiRequest( api= "GET /person/changes", argumentCollection= arguments );
	}

	// ---------------------------------------------------------------------------------------- 
	// COMPANY METHODS 
	// ---------------------------------------------------------------------------------------- 

	struct function getCompany( required string company_id ) {
		return this.apiRequest( api= "GET /company/{company_id}", argumentCollection= arguments );
	}

	struct function getCompanyMovies( required string company_id, string language= this.defaultLanguage ) {
		return this.apiRequest( api= "GET /company/{company_id}/movies", argumentCollection= arguments );
	}
	
	// ---------------------------------------------------------------------------------------- 
	// MISC METHODS 
	// ---------------------------------------------------------------------------------------- 

	struct function getConfig( boolean force= false ) {
		if ( arguments.force || structKeyExists( this, "config" ) ) {
			var out= this.apiRequest( api= "GET /configuration", argumentCollection= arguments );
			if ( out.success ) {
				this.config= out.data;
			}
		}
		return this.config;
	}

	struct function getCountries() {
		return this.apiRequest( api= "GET /configuration/countries", argumentCollection= arguments );
	}

	struct function getJobs() {
		return this.apiRequest( api= "GET /configuration/jobs", argumentCollection= arguments );
	}

	struct function getLanguages() {
		return this.apiRequest( api= "GET /configuration/languages", argumentCollection= arguments );
	}

	struct function getTranslations() {
		return this.apiRequest( api= "GET /configuration/primary_translations", argumentCollection= arguments );
	}

	struct function getTimezones() {
		return this.apiRequest( api= "GET /configuration/timezones", argumentCollection= arguments );
	}

	struct function getCollection( required string collection_id ) {
		return this.apiRequest( api= "GET /collection/{collection_id}", argumentCollection= arguments );
	}

	struct function getCollectionImages( required string collection_id, string language= this.defaultLanguage ) {
		return this.apiRequest( api= "GET /collection/{collection_id}/images", argumentCollection= arguments );
	}

	struct function getReview( required string review_id ) {
		return this.apiRequest( api= "GET /review/{review_id}", argumentCollection= arguments );
	}

	struct function getNetwork( required string network_id ) {
		return this.apiRequest( api= "GET /network/{network_id}", argumentCollection= arguments );
	}

	struct function getKeyword( required string keyword_id ) {
		return this.apiRequest( api= "GET /keyword/{keyword_id}", argumentCollection= arguments );
	}

	struct function getKeywordMovies( required string keyword_id ) {
		return this.apiRequest( api= "GET /keyword/{keyword_id}/movies", argumentCollection= arguments );
	}

	string function imdbID( numeric input= true ) {
		if ( isNumeric( arguments.input ) ) {
			if( arguments.input >= 10000000 ) {
				arguments.input= "tt" & numberFormat( arguments.input, "00000000" );
			} else {
				arguments.input= "tt" & numberFormat( arguments.input, "0000000" );
			}
		}
		return arguments.input;
	}

	string function structToQueryString( required struct stInput, boolean bEncode= true ) {
		var sOutput= "";
		var sItem= "";
		var sValue= "";
		var amp= "?";
		for ( sItem in stInput ) {
			sValue= stInput[ sItem ];
			if ( !isNull( sValue ) && len( sValue ) ) {
				if ( bEncode ) {
					sOutput &= amp & sItem & "=" & urlEncodedFormat( sValue );
				} else {
					sOutput &= amp & sItem & "=" & sValue;
				}
				amp= "&";
			}
		}
		return sOutput;
	}

}
