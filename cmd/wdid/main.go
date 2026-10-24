package main

import (
	"context"
	"embed"
	"io/fs"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/Mallekoppie/goslow/platform"
	"go.uber.org/zap"

	"github.com/Mallekoppie/wdid/internal/auth"
	"github.com/Mallekoppie/wdid/internal/config"
	"github.com/Mallekoppie/wdid/internal/rpc"
	"github.com/Mallekoppie/wdid/internal/store"
)

//go:embed all:dist
var webAssets embed.FS

// nonRPCRoutes returns the plain-HTTP routes. Liveness is the only one; every
// domain capability is served through Connect.
func nonRPCRoutes() platform.Routes {
	return platform.Routes{
		{Path: "/healthz", Method: http.MethodGet, Auth: platform.AuthNone, HandlerFunc: health, SlaMs: 50},
	}
}

func health(w http.ResponseWriter, _ *http.Request) {
	platform.JsonMarshaller.WriteJsonResponse(w, http.StatusOK, map[string]string{"status": "ok"})
}

func main() {
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "invite":
			if err := runInvite(os.Args[2:], os.Stdout); err != nil {
				log.Fatalf("wdid invite: %v", err)
			}
			return
		case "backup":
			if err := runBackup(os.Args[2:], os.Stdout); err != nil {
				log.Fatalf("wdid backup: %v", err)
			}
			return
		case "restore":
			if err := runRestore(os.Args[2:], os.Stdout); err != nil {
				log.Fatalf("wdid restore: %v", err)
			}
			return
		}
	}

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

	assets, err := fs.Sub(webAssets, "dist")
	if err != nil {
		return err
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// The scheduler checks for an overdue backup at startup and then at each
	// configured interval. It shares its manager with SettingsService so a
	// manual backup and a settings change are visible in the status.
	backupManager := newBackupManager(database, cfg)
	go backupManager.Run(ctx)

	platform.Log.Info("starting wdid service",
		zap.String("address", cfg.HTTPAddr),
		zap.String("database", cfg.DBPath),
		zap.Bool("zitadel", cfg.Zitadel.Enabled),
		zap.Bool("reflection", cfg.DevMode),
	)

	// One listener serves Connect, native gRPC, gRPC-Web, the liveness route,
	// and the embedded Flutter app.
	return platform.StartApplicationServerWithContext(ctx, platform.ApplicationServerOptions{
		Services: []platform.ConnectService{
			rpc.NewAuthService(database, authService, cfg),
			rpc.NewCategoryService(database, authService),
			rpc.NewEntryService(database, authService),
			rpc.NewTimerService(database, authService),
			rpc.NewSettingsService(database, authService, rpc.WithBackupManager(backupManager)),
			rpc.NewSummaryService(database, authService, rpc.WithSummaryAPIKey(cfg.OpenAIAPIKey)),
			rpc.NewNoteService(database, authService),
			rpc.NewMilestoneService(database, authService),
			rpc.NewCheckInService(database, authService),
		},
		ServiceNames: []string{
			config.AuthServiceName,
			config.CategoryServiceName,
			config.EntryServiceName,
			config.TimerServiceName,
			config.SettingsServiceName,
			config.SummaryServiceName,
			config.NoteServiceName,
			config.MilestoneServiceName,
			config.CheckInServiceName,
		},
		Routes: nonRPCRoutes(),
		SPA: &platform.SPAOptions{
			Assets: assets,
			Index:  "index.html",
		},
		AllowedOrigins: cfg.AllowedOrigins,
	})
}
