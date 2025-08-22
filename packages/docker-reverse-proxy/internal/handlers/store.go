package handlers

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"

	"github.com/e2b-dev/infra/packages/docker-reverse-proxy/internal/cache"
	"github.com/e2b-dev/infra/packages/shared/pkg/consts"
	"github.com/e2b-dev/infra/packages/shared/pkg/db"
)

type APIStore struct {
	db        *db.DB
	AuthCache *cache.AuthCache
	proxy     *httputil.ReverseProxy
}

func NewStore() *APIStore {
	authCache := cache.New()
	database, err := db.NewClient(3, 2)
	if err != nil {
		log.Fatal(err)
	}

	var targetUrl *url.URL
	
	// In development mode, use local registry instead of GCP
	if os.Getenv("ENVIRONMENT") == "development" {
		localRegistryURL := os.Getenv("LOCAL_REGISTRY_URL")
		if localRegistryURL == "" {
			localRegistryURL = "http://local-registry:5000"
		}
		targetUrl, err = url.Parse(localRegistryURL)
		if err != nil {
			log.Fatal(fmt.Errorf("failed to parse LOCAL_REGISTRY_URL: %w", err))
		}
		log.Printf("Development mode: proxying to local registry at %s", targetUrl.String())
	} else {
		targetUrl = &url.URL{
			Scheme: "https",
			Host:   fmt.Sprintf("%s-docker.pkg.dev", consts.GCPRegion),
		}
		log.Printf("Production mode: proxying to GCP registry at %s", targetUrl.String())
	}

	proxy := httputil.NewSingleHostReverseProxy(targetUrl)

	// Custom ModifyResponse function
	proxy.ModifyResponse = func(resp *http.Response) error {
		if resp.StatusCode == http.StatusUnauthorized {
			respBody, _ := io.ReadAll(resp.Body)
			log.Printf("Unauthorized request:[%s] %s\n", resp.Request.Method, respBody)
		}

		// In development mode, rewrite Location headers from local registry to external domain
		if os.Getenv("ENVIRONMENT") == "development" {
			if location := resp.Header.Get("Location"); location != "" {
				externalDomain := os.Getenv("EXTERNAL_REGISTRY_DOMAIN")
				if externalDomain == "" {
					externalDomain = "docker.localhost"
				}
				
				localRegistryHost := os.Getenv("LOCAL_REGISTRY_HOST")
				if localRegistryHost == "" {
					localRegistryHost = "local-registry:5000"
				}
				
				// Replace internal registry URL with external domain
				httpsPrefix := fmt.Sprintf("https://%s/", localRegistryHost)
				httpPrefix := fmt.Sprintf("http://%s/", localRegistryHost)
				externalPrefix := fmt.Sprintf("https://%s/", externalDomain)
				
				if strings.HasPrefix(location, httpsPrefix) {
					newLocation := strings.Replace(location, httpsPrefix, externalPrefix, 1)
					resp.Header.Set("Location", newLocation)
					log.Printf("Rewrote Location header: %s -> %s", location, newLocation)
				} else if strings.HasPrefix(location, httpPrefix) {
					newLocation := strings.Replace(location, httpPrefix, externalPrefix, 1)
					resp.Header.Set("Location", newLocation)
					log.Printf("Rewrote Location header: %s -> %s", location, newLocation)
				}
			}
		}

		return nil
	}

	return &APIStore{
		db:        database,
		AuthCache: authCache,
		proxy:     proxy,
	}
}

func (a *APIStore) ServeHTTP(rw http.ResponseWriter, req *http.Request) {
	// Set the host to the URL host
	req.Host = req.URL.Host

	a.proxy.ServeHTTP(rw, req)
}
