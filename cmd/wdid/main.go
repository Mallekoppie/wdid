package main

import (
	"context"
	"embed"
	"io/fs"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/Mallekoppie/goslow/platform"
	"go.uber.org/zap"

	"github.com/Mallekoppie/wdid/internal/api"
	"github.com/Mallekoppie/wdid/internal/auth"
	"github.com/Mallekoppie/wdid/internal/config"
	"github.com/Mallekoppie/wdid/internal/rpc"
	"github.com/Mallekoppie/wdid/internal/store"
)

//go:embed all:dist
var webAssets embed.FS

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

	assets, err := fs.Sub(webAssets, "dist")
	if err != nil {
		return err
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	platform.Log.Info("starting wdid service",
		zap.String("address", cfg.HTTPAddr),
		zap.String("database", cfg.DBPath),
		zap.Bool("zitadel", cfg.Zitadel.Enabled),
		zap.Bool("reflection", cfg.DevMode),
	)

	// One listener serves Connect, native gRPC, gRPC-Web, the legacy REST
	// routes during migration, and the embedded Flutter app.
	return platform.StartApplicationServerWithContext(ctx, platform.ApplicationServerOptions{
		Services: []platform.ConnectService{
			rpc.NewAuthService(database, authService, cfg),
		},
		ServiceNames: []string{config.AuthServiceName},
		Routes:       handler.Routes(),
		SPA: &platform.SPAOptions{
			Assets: assets,
			Index:  "index.html",
		},
		AllowedOrigins: cfg.AllowedOrigins,
	})
}
