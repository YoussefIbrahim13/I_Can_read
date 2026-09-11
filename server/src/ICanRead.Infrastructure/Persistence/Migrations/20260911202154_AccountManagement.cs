using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ICanRead.Infrastructure.Persistence.Migrations
{
    /// <summary>
    /// Email verification, sign-in lockout, session metadata, and one code table
    /// serving both the reset flow and the new verification flow.
    /// </summary>
    /// <remarks>
    /// Hand-edited away from what was scaffolded. EF saw
    /// <c>password_reset_codes</c> disappear and <c>account_codes</c> appear and
    /// wrote a drop and a create, which is correct for the schema and wrong for
    /// the rows: a reader who asked for a reset code a minute before the deploy
    /// would find it had stopped existing. A rename plus a defaulted column says
    /// the same thing about the schema and keeps them.
    /// </remarks>
    public partial class AccountManagement : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.RenameTable(
                name: "password_reset_codes",
                newName: "account_codes");

            // Postgres carries constraint and index names through a table
            // rename untouched, so they have to be brought across by hand or
            // the next migration would be reasoning about names that no longer
            // describe anything.
            migrationBuilder.Sql(
                """
                ALTER TABLE account_codes
                    RENAME CONSTRAINT "PK_password_reset_codes" TO "PK_account_codes";
                """);

            migrationBuilder.Sql(
                """
                ALTER TABLE account_codes
                    RENAME CONSTRAINT "FK_password_reset_codes_users_UserId"
                    TO "FK_account_codes_users_UserId";
                """);

            migrationBuilder.DropIndex(
                name: "IX_password_reset_codes_UserId_CreatedAt",
                table: "account_codes");

            // Added nullable and backfilled rather than added with a default:
            // a DB-level default would linger as a difference from the model
            // that a later migration would have to come back and remove.
            migrationBuilder.AddColumn<string>(
                name: "Purpose",
                table: "account_codes",
                type: "character varying(32)",
                maxLength: 32,
                nullable: true);

            migrationBuilder.Sql(
                """
                UPDATE account_codes SET "Purpose" = 'PasswordReset'
                WHERE "Purpose" IS NULL;
                """);

            migrationBuilder.AlterColumn<string>(
                name: "Purpose",
                table: "account_codes",
                type: "character varying(32)",
                maxLength: 32,
                nullable: false,
                oldClrType: typeof(string),
                oldType: "character varying(32)",
                oldMaxLength: 32,
                oldNullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_account_codes_UserId_Purpose_CreatedAt",
                table: "account_codes",
                columns: new[] { "UserId", "Purpose", "CreatedAt" });

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "EmailVerifiedAt",
                table: "users",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "FailedSignInCount",
                table: "users",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "LockedUntil",
                table: "users",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "CreatedFromIp",
                table: "refresh_tokens",
                type: "character varying(45)",
                maxLength: 45,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "UserAgent",
                table: "refresh_tokens",
                type: "character varying(256)",
                maxLength: 256,
                nullable: true);

            // The sessions list orders by age, so the index it reads carries
            // the date. Sessions issued before this deploy keep working and
            // simply have nothing to say about where they came from.
            migrationBuilder.DropIndex(
                name: "IX_refresh_tokens_UserId",
                table: "refresh_tokens");

            migrationBuilder.CreateIndex(
                name: "IX_refresh_tokens_UserId_CreatedAt",
                table: "refresh_tokens",
                columns: new[] { "UserId", "CreatedAt" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_refresh_tokens_UserId_CreatedAt",
                table: "refresh_tokens");

            migrationBuilder.CreateIndex(
                name: "IX_refresh_tokens_UserId",
                table: "refresh_tokens",
                column: "UserId");

            migrationBuilder.DropColumn(name: "UserAgent", table: "refresh_tokens");
            migrationBuilder.DropColumn(name: "CreatedFromIp", table: "refresh_tokens");
            migrationBuilder.DropColumn(name: "LockedUntil", table: "users");
            migrationBuilder.DropColumn(name: "FailedSignInCount", table: "users");
            migrationBuilder.DropColumn(name: "EmailVerifiedAt", table: "users");

            migrationBuilder.DropIndex(
                name: "IX_account_codes_UserId_Purpose_CreatedAt",
                table: "account_codes");

            // Verification codes have no home in the old shape. They live
            // fifteen minutes, so dropping them costs a reader one tap on
            // "send it again".
            migrationBuilder.Sql(
                """DELETE FROM account_codes WHERE "Purpose" <> 'PasswordReset';""");

            migrationBuilder.DropColumn(name: "Purpose", table: "account_codes");

            migrationBuilder.Sql(
                """
                ALTER TABLE account_codes
                    RENAME CONSTRAINT "FK_account_codes_users_UserId"
                    TO "FK_password_reset_codes_users_UserId";
                """);

            migrationBuilder.Sql(
                """
                ALTER TABLE account_codes
                    RENAME CONSTRAINT "PK_account_codes" TO "PK_password_reset_codes";
                """);

            migrationBuilder.RenameTable(
                name: "account_codes",
                newName: "password_reset_codes");

            migrationBuilder.CreateIndex(
                name: "IX_password_reset_codes_UserId_CreatedAt",
                table: "password_reset_codes",
                columns: new[] { "UserId", "CreatedAt" });
        }
    }
}
