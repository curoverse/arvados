// Copyright (C) The Arvados Authors. All rights reserved.
//
// SPDX-License-Identifier: AGPL-3.0

package controller

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"strings"

	"git.arvados.org/arvados.git/sdk/go/auth"
	"git.arvados.org/arvados.git/sdk/go/httpserver"
)

func remoteContainerRequestCreate(
	h *genericFederatedRequestHandler,
	effectiveMethod string,
	clusterID *string,
	uuid string,
	remainder string,
	w http.ResponseWriter,
	req *http.Request) bool {

	if effectiveMethod != "POST" || uuid != "" || remainder != "" {
		return false
	}

	// First make sure supplied token is valid.
	creds := auth.NewCredentials()
	creds.LoadTokensFromHTTPRequest(req)

	currentUser, ok, err := h.handler.validateAPItoken(req, creds.Tokens[0])
	if err != nil {
		httpserver.Error(w, err.Error(), http.StatusInternalServerError)
		return true
	} else if !ok {
		httpserver.Error(w, "invalid API token", http.StatusForbidden)
		return true
	}

	if *clusterID == "" || *clusterID == h.handler.Cluster.ClusterID {
		// Submitting container request to local cluster. No
		// need to set a runtime_token (rails api will create
		// one when the container runs) or do a remote cluster
		// request.
		return false
	}

	if req.Header.Get("Content-Type") != "application/json" {
		httpserver.Error(w, "Expected Content-Type: application/json, got "+req.Header.Get("Content-Type"), http.StatusBadRequest)
		return true
	}

	originalBody := req.Body
	defer originalBody.Close()
	var request map[string]interface{}
	err = json.NewDecoder(req.Body).Decode(&request)
	if err != nil {
		httpserver.Error(w, err.Error(), http.StatusBadRequest)
		return true
	}

	crString, ok := request["container_request"].(string)
	if ok {
		var crJSON map[string]interface{}
		err := json.Unmarshal([]byte(crString), &crJSON)
		if err != nil {
			httpserver.Error(w, err.Error(), http.StatusBadRequest)
			return true
		}

		request["container_request"] = crJSON
	}

	containerRequest, ok := request["container_request"].(map[string]interface{})
	if !ok {
		// Use toplevel object as the container_request object
		containerRequest = request
	}

	// If runtime_token is not set, create a new token
	if _, ok := containerRequest["runtime_token"]; !ok {
		if len(currentUser.Authorization.Scopes) != 1 || currentUser.Authorization.Scopes[0] != "all" {
			httpserver.Error(w, "Token scope is not [all]", http.StatusForbidden)
			return true
		}

		if strings.HasPrefix(currentUser.Authorization.UUID, h.handler.Cluster.ClusterID) {
			// Local user, submitting to a remote cluster.
			// Create a new time-limited token.
			newtok, err := h.handler.createAPItoken(req, currentUser.UUID, nil)
			if err != nil {
				httpserver.Error(w, err.Error(), http.StatusForbidden)
				return true
			}
			containerRequest["runtime_token"] = newtok.TokenV2()
		} else {
			// Remote user. Container request will use the
			// current token, minus the trailing portion
			// (optional container uuid).
			sp := strings.Split(creds.Tokens[0], "/")
			if len(sp) >= 3 {
				containerRequest["runtime_token"] = strings.Join(sp[0:3], "/")
			} else {
				containerRequest["runtime_token"] = creds.Tokens[0]
			}
		}
	}

	newbody, err := json.Marshal(request)
	buf := bytes.NewBuffer(newbody)
	req.Body = ioutil.NopCloser(buf)
	req.ContentLength = int64(buf.Len())
	req.Header.Set("Content-Length", fmt.Sprintf("%v", buf.Len()))

	resp, err := h.handler.remoteClusterRequest(*clusterID, req)
	h.handler.proxy.ForwardResponse(w, resp, err)
	return true
}
