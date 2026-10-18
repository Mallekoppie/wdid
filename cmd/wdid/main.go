package main

import (
	"log"

	"github.com/Mallekoppie/goslow/platform"
	"go.uber.org/zap"

	"github.com/Mallekoppie/wdid/internal/api"
	"github.com/Mallekoppie/wdid/internal/auth"
	"github.com/Mallekoppie/wdid/internal/config"
	"github.com/Mallekoppie/wdid/internal/store"
)

func main() {
	if err := run(); err != nil {
		log.Fatalf("wdid: %v", err)
	}
}

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	database, err := store.Open(cfg)
	if err != nil {
		return err
	}
	defer database.Close()

	authService := auth.NewService(database, cfg)
	handler := api.New(database, authService, cfg)

	platform.Log.Info("starting wdid service",
		zap.String("address", cfg.HTTPAddr),
		zap.String("database", cfg.DBPath),
		zap.Bool("zitadel", cfg.Zitadel.Enabled),
	)

	// goslow owns the HTTP server lifecycle and closes the database when the
	// listener stops.
	return platform.StartHttpServer(handler.Routes())
}
