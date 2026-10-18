package api

import (
	"errors"
	"net/http"
	"time"

	"github.com/Mallekoppie/wdid/internal/auth"
	"github.com/Mallekoppie/wdid/internal/domain"
)

func (a *API) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

type authResponse struct {
	User  domain.User `json:"user"`
	Token string      `json:"token"`
}

func (a *API) register(w http.ResponseWriter, r *http.Request) {
	var request auth.RegisterRequest
	if err := decodeJSON(r, &request); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", err.Error())
		return
	}

	user, token, err := a.auth.Register(request, time.Now().UTC())
	if err != nil {
		a.writeAuthError(w, err)
		return
	}

	writeJSON(w, http.StatusCreated, authResponse{User: user, Token: token})
}

func (a *API) login(w http.ResponseWriter, r *http.Request) {
	var request struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := decodeJSON(r, &request); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", err.Error())
		return
	}

	user, token, err := a.auth.Login(request.Email, request.Password)
	if err != nil {
		a.writeAuthError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, authResponse{User: user, Token: token})
}

func (a *API) me(w http.ResponseWriter, r *http.Request) {
	identity, ok := caller(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "a valid bearer token is required")
		return
	}

	user, err := a.store.UserByID(identity.UserID)
	if err != nil {
		writeServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, user)
}

func (a *API) authConfig(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"localLogin":          true,
		"registrationEnabled": len(a.cfg.RegistrationSecret) > 0,
		"oidc": map[string]interface{}{
			"enabled":   a.cfg.Zitadel.Enabled,
			"issuerUrl": a.cfg.Zitadel.IssuerURL,
			"clientId":  a.cfg.Zitadel.ClientID,
		},
	})
}

func (a *API) writeAuthError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, auth.ErrInvalidRegistrationSecret):
		writeError(w, http.StatusForbidden, "registration_secret_invalid", "the registration secret is not valid")
	case errors.Is(err, auth.ErrInvalidCredentials):
		writeError(w, http.StatusUnauthorized, "invalid_credentials", "invalid email or password")
	default:
		writeServiceError(w, err)
	}
}
