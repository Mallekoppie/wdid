package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"text/tabwriter"
	"time"

	"github.com/Mallekoppie/wdid/internal/config"
	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/invite"
	"github.com/Mallekoppie/wdid/internal/store"
)

// runInvite dispatches the `wdid invite` subcommands.
func runInvite(args []string, out io.Writer) error {
	if len(args) == 0 {
		return errors.New("usage: wdid invite create --email <address> | list | revoke <id>")
	}

	switch args[0] {
	case "create":
		return runInviteCreate(args[1:], out)
	case "list":
		return runInviteList(args[1:], out)
	case "revoke":
		return runInviteRevoke(args[1:], out)
	default:
		return fmt.Errorf("unknown invite command %q", args[0])
	}
}

func runInviteCreate(args []string, out io.Writer) error {
	flags := flag.NewFlagSet("invite create", flag.ContinueOnError)
	flags.SetOutput(out)
	flags.Usage = func() {
		fmt.Fprintln(out, "usage: wdid invite create --email <address>")
	}
	email := flags.String("email", "", "email address the invite is issued to")
	if err := flags.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return nil
		}
		return err
	}
	if err := domain.ValidateEmail(*email); err != nil {
		return err
	}

	code, err := invite.New()
	if err != nil {
		return err
	}

	record := domain.Invite{
		ID:        domain.NewID(),
		Email:     *email,
		CreatedAt: time.Now().UTC(),
	}
	record.Normalize()

	database, err := openCLIStore()
	if err != nil {
		return err
	}
	defer database.Close()

	if err := database.CreateInvite(record, invite.Hash(code)); err != nil {
		return err
	}

	fmt.Fprintf(out, "Created invite %s for %s\n", record.ID, record.Email)
	fmt.Fprintf(out, "Invite code: %s\n", code)
	fmt.Fprintln(out, "The code is shown once; only its hash is stored.")
	return nil
}

func runInviteList(args []string, out io.Writer) error {
	if len(args) > 0 {
		return errors.New("usage: wdid invite list")
	}

	database, err := openCLIStore()
	if err != nil {
		return err
	}
	defer database.Close()

	invites, err := database.Invites()
	if err != nil {
		return err
	}
	if len(invites) == 0 {
		fmt.Fprintln(out, "No invites.")
		return nil
	}

	table := tabwriter.NewWriter(out, 0, 4, 2, ' ', 0)
	fmt.Fprintln(table, "ID\tEMAIL\tSTATUS\tCREATED\tUSED BY")
	for _, record := range invites {
		status := "unused"
		usedBy := "-"
		if record.UsedAt != nil {
			status = "used"
			usedBy = record.UsedBy
		}
		fmt.Fprintf(table, "%s\t%s\t%s\t%s\t%s\n",
			record.ID, record.Email, status, record.CreatedAt.Format(time.RFC3339), usedBy)
	}
	return table.Flush()
}

func runInviteRevoke(args []string, out io.Writer) error {
	if len(args) != 1 {
		return errors.New("usage: wdid invite revoke <id>")
	}

	database, err := openCLIStore()
	if err != nil {
		return err
	}
	defer database.Close()

	if err := database.RevokeInvite(args[0]); err != nil {
		return err
	}

	fmt.Fprintf(out, "Revoked invite %s\n", args[0])
	return nil
}

func openCLIStore() (*store.Store, error) {
	database, err := store.Open(config.LoadStorage())
	if err != nil {
		return nil, fmt.Errorf(
			"open database (stop the running service before managing invites): %w", err)
	}
	return database, nil
}
