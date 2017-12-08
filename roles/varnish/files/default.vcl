#
# Magento backend definition 
#
backend nginx {
    .host = "127.0.0.1";
    .port = "8080";
    .connect_timeout = 1800s;
    .first_byte_timeout = 1800s;
    .between_bytes_timeout = 1800s;
}


#
# vcl_recv is called when a client request is received by Varnish
#
sub vcl_recv {
    set req.backend = nginx;
    set req.http.X-Forwarded-Port = server.port;
    set req.http.X-Forwarded-Proto = "http";

    #Authorization
    #if (req.http.Authorization || req.http.Authenticate)
    #	{
    #		  return (pass);
    #	}
    
    # SSL traffic
    if (server.port == 81) {
        set req.http.X-Forwarded-Port = "443";
        set req.http.X-Forwarded-Proto = "https";
    }

    # Add a unique header containing the client address
    if (req.restarts == 0) {
        if (req.http.X-Forwarded-For) {
            set req.http.X-Forwarded-For = req.http.X-Forwarded-For + ", " + client.ip;
        } else {
            set req.http.X-Forwarded-For = client.ip;
        }
    }

    # Only cache GET or HEAD requests. This makes sure the POST requests are always passed.
    if (req.request != "GET" && req.request != "HEAD") {
        return (pass);
    }

    # Do not cache auth request
    if (req.http.Authorization) {
        return (pass);
    }

   #Blackfire integration
   #if (req.http.X-Blackfire-Query) {
   #     return (pass);
   #}

    #if (req.http.Cache-Control ~ "no-cache") {
    #    ban_url(req.url);
    #}

    # The grace period allow to serve cached entry after expiration while 
    # a new version is being fetched from the backend
    set req.grace = 30s;

    # Each cache entry on Varnish is based on a key (provided by vcl_hash)
    # AND the Vary header. This header, sent by the server, define on which
    # client header the cache entry must vary. And for each different value of
    # the specified client header, a new cache entry on the same key will be created.
    # 
    # In case of compression, the mod_deflate on the Apache backend will add 
    # "Vary: Accept-Encoding", as some HTTP client does not support the compression
    # and some support only gzip, and some gzip and deflate. The last ones are the
    # majority but they do not advertise "gzip" and "deflate" in the same order. So to avoid
    # storing a different cache for "gzip,deflate" and "deflate,gzip", we turn the
    # accept-encoding into just "gzip".
    # We do not take into account "deflate" only browsers, as they have only a theorical
    # existence ;) Worst case: they will receive the uncompressed format.
    # 
    # So at the end we would have only 2 versions for the same cache entry:
    #     - gziped
    #     - uncompressed
    if (req.http.Accept-Encoding) {
        if (req.http.Accept-Encoding ~ "gzip") {
          set req.http.Accept-Encoding = "gzip";
        } else {
            unset req.http.Accept-Encoding;
        }
    }

    # Health check from LB
    if (req.url == "/status.html") {
        return (pass);
    }

    # Not cachable content from Magento
    if (req.url ~ "/varnish/ajax/call/"
        || req.url ~ "/returns/"
        || req.url ~ "/catalog/product_compare/"
        || req.url ~ "/atos/"
        || req.url ~ "/checkout/"
        || req.url ~ "/client/"
        || req.url ~ "/customer/"
        || req.url ~ "/egift-certificate.html"
        || req.url ~ "/sales/"
        || req.url ~ "/wishlist/"
        || req.url ~ "/review/"
        || req.url ~ "/api/"
        || req.url ~ "/sendfriend/"
        || req.url ~ "/admin"
        || req.url ~ "/mon-compte/"
        || req.url ~ "/account/"
        || req.url ~ "/catalog/product_compare/"
        || req.url ~ "/order/"
        || req.url ~ "/giftcard/customer/"
        || req.url ~ "/storecredit/"
        || req.url ~ "/storelocator/index/search/"
        || req.url ~ "/storelocator/"
        || req.url ~ "/store-locator/"
        || req.url ~ "/punti-vendita/"
        || req.url ~ "/storelocator/index/getStores/"
        || req.url ~ "/relay/"
        || req.url ~ "/globalcollect/"
        || req.url ~ "/catalogsearch/"
        || req.url ~ "/simplesaml/"
        || req.url ~ "/salesforceapi/"
        #newsletter
        || req.url ~ "newsletter" || req.url ~ "boletin" || req.url ~ "nieuwsbrief"
        #Contact us
        || req.url ~ "/contacts/" || req.url ~ "/contact-us/" || req.url ~ "/contacto" || req.url ~ "/kontakt"
        || req.url ~ "/contact"   || req.url ~ "/contattaci/"
        ## / is used for redirect the user to the correct store
        #|| req.url == "/"
    ) {
        return (pass);
    }

    # Large static files should be piped, so they are delivered directly to the end-user without
    # waiting for Varnish to fully read the file first.
    if (req.url ~ "^[^?]*\.(7z|avi|bz2|flac|flv|gz|mka|mkv|mov|mp3|mp4|mpeg|mpg|ogg|ogm|opus|rar|tar|tgz|tbz|txz|wav|webm|xz|zip)(\?.*)?$") {
        unset req.http.Cookie;
        return (pipe);
    }

    # Turpentine
    if (req.url ~ "/turpentine/esi/get(?:Block|FormKey)/") {
        set req.http.X-Varnish-Esi-Method = regsub(req.url, ".*/method/(\w+)/.*", "\1");
        set req.http.X-Varnish-Esi-Access = regsub(req.url, ".*/access/(\w+)/.*", "\1");
    }
    if (req.http.Cookie !~ "frontend=" && req.http.User-Agent ~ "^(?:ApacheBench/.*|.*Googlebot.*|JoeDog/.*Siege.*|magespeedtest\.com|Nexcessnet_Turpentine/.*)$") {
        set req.http.Cookie = "frontend=crawler-session";
    }

    if (req.url ~ "[?&](utm_source|utm_medium|utm_campaign|utm_content|utm_term|gclid|cx|ie|cof|siteurl)=") {
        set req.url = regsuball(req.url, "(?:(\?)?|&)(?:utm_source|utm_medium|utm_campaign|utm_content|utm_term|gclid|cx|ie|cof|siteurl)=[^&]+", "\1");
        set req.url = regsuball(req.url, "(?:(\?)&|\?$)", "\1");
    }

    if (req.url ~ ".*\.(?:css|js|jpe?g|png|gif|ico|swf)(?=\?|&|$)") {
        unset req.http.Cookie;
    }

    return(lookup);
}
 
#
# vcl_fetch is executed when the response come back from the backend
#
sub vcl_fetch {

    # This cookie is set when pass is call in vcl_recv
    # meaning it is not a cachable content
    if ( req.http.X-Varnish-Pass == "y" ) {
        return(deliver);
    }

    set beresp.grace = 30s;

    # Store the URL in the response object, to be able to do lurker friendly bans later
    set beresp.http.X-Varnish-Host = req.http.host;
    set beresp.http.X-Varnish-URL = req.url;

    # Enable ESI
    #if (req.url == "/tools/varnish-esi/container.html"
    #    || req.url ~ "/blog"
    #    || req.url ~ ".html"
    #    || req.url ~ "catalog/product/view"
    #    || req.url ~ "/seo/index/description/"
    #    || req.url ~ "test-esi"
    #    || beresp.http.X-Turpentine-Esi == "1"
    #    || req.url ~ "."
    #) {
    #    set beresp.do_esi = true; /* Do ESI processing */
    #    set beresp.ttl = 1h; /* Sets the TTL on the HTML above  */
    #}

    #ESI tag for SEO meta description
    #if (req.url ~ "/seo/index/description/") {
    #   set beresp.do_esi = true;
    #   set beresp.ttl = 1h;
    #}

    # Do not cache 302 temporary redirect and 50x errors
    if (beresp.status == 302 || beresp.status >= 500) {
        return (hit_for_pass);
    }

    # Define cache time depending on type, URL or status code
    if (beresp.status == 301 || (beresp.status >=400 && beresp.status < 500)) {
        # Permanent redirections and client error cached for a short time
        set beresp.ttl = 120s;
    } elsif (req.url ~ "\.(gif|jpg|jpeg|bmp|png|tiff|tif|ico|img|tga|wmf)$" || req.url ~ "/skin/") {
        set beresp.ttl = 2h;
    } else {
        # Default for all other ressources, included pages.
        set beresp.ttl = 24h;
        set beresp.do_gzip = true;
    }

    unset beresp.http.Set-Cookie;
    return (deliver);
}

sub vcl_pipe {
    # Note that only the first request to the backend will have
    # X-Forwarded-For set.  If you use X-Forwarded-For and want to
    # have it set for all requests, make sure to have:
    # set bereq.http.connection = "close";
    # here.  It is not set by default as it might break some broken web
    # applications, like IIS with NTLM authentication.

    set bereq.http.Connection = "Close";

    # Needed for WS (Websocket) support: https://www.varnish-cache.org/docs/3.0/tutorial/websockets.html
    if (req.http.upgrade) {
        set bereq.http.upgrade = req.http.upgrade;
    }

    return (pipe);
}

sub vcl_pass {
    set req.http.X-Varnish-Pass="y";
    return (pass);
}
 
sub vcl_hash {
    hash_data(req.url);

    if (req.http.host) {
        hash_data(req.http.host);
    } else {
        hash_data(server.ip);
    }

    if (req.http.Accept-Encoding) {
        hash_data(req.http.Accept-Encoding);
    }

    if (req.http.X-Forwarded-Proto && req.url !~ "/media/" && req.url !~ "/skin/") {
        hash_data(req.http.X-Forwarded-Proto);
    }

    return (hash);
}
 
sub vcl_hit {
    return (deliver);
}

sub vcl_miss {
    return (fetch);
}

#
# vcl_deliver is called when sending the response to the client.
# Some headers are added to help debug
# 
sub vcl_deliver {
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
        set resp.http.X-Cache-Hits = obj.hits;
    }
    else {
        set resp.http.X-Cache = "MISS";
    }
    # Set myfrontal ID
    set resp.http.X-Front = server.hostname;

    # Unset control headers that might confuse the browser when obj.ttl > max-age (for static objects)
    # Browser caching only relies on Cache-Control: max-age
    unset resp.http.Expires;
    unset resp.http.Age;

    # Prevent disclosure
    unset resp.http.Via;
    unset resp.http.X-Powered-By;

    # remove Varnish fingerprints
    unset resp.http.X-Varnish-Host;
    unset resp.http.X-Varnish-URL;

    return (deliver);
}
 
sub vcl_init {
    return (ok);
}

sub vcl_fini {
    return (ok);
}

sub vcl_error {

    set obj.http.Content-Type = "text/html; charset=utf-8";
    set obj.http.Retry-After = "5";

    synthetic {"<!DOCTYPE html>
<html lang="en">
  <head>
        <meta charset="utf-8">
        <title>"} + obj.status + " " + obj.response + {"</title>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <meta name="description" content="Backend Error page">
        <meta name="author" content="Pascal A.">
        <meta name="generator" content="vim">
        <meta http-equiv="Content-Type" content="text/html;charset=utf-8" >
        <!-- Le styles -->
        <link href="//netdna.bootstrapcdn.com/twitter-bootstrap/2.2.1/css/bootstrap-combined.min.css" rel="stylesheet">
        <style>
            body {
                padding-top: 60px; /* 60px to make the container go all the way to the bottom of the topbar */
            }
    </style>
        <!-- Le HTML5 shim, for IE6-8 support of HTML5 elements -->
        <!--[if lt IE 9]>
        <script src="//html5shim.googlecode.com/svn/trunk/html5.js"></script>
        <![endif]-->
  </head>
  <body>
        <div class="container">
            <div class="page-header">
                <h1 class="pagination-centered">Error "} + obj.status + " " + obj.response + {"</h1>
            </div>
            <div class="alert alert-error pagination-centered">
                <i class="icon-warning-sign"></i>
                We're very sorry, but the page could not be loaded properly.
                <i class="icon-warning-sign"></i>
            </div>
            <blockquote>This should be fixed very soon, and we apologize for any inconvenience.</blockquote>
        </div>
        <footer class="container pagination-centered">
        </footer>
  </body>
</html>
"};
    return (deliver);
}
