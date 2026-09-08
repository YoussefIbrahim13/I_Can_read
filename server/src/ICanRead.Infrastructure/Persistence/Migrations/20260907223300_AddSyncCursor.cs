using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ICanRead.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddSyncCursor : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_books_UserId_UpdatedAt",
                table: "books");

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "ServerUpdatedAt",
                table: "reading_sessions",
                type: "datetimeoffset",
                nullable: false,
                defaultValue: new DateTimeOffset(new DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)));

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "ServerUpdatedAt",
                table: "reading_plans",
                type: "datetimeoffset",
                nullable: false,
                defaultValue: new DateTimeOffset(new DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)));

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "ServerUpdatedAt",
                table: "reading_log",
                type: "datetimeoffset",
                nullable: false,
                defaultValue: new DateTimeOffset(new DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)));

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "ServerUpdatedAt",
                table: "books",
                type: "datetimeoffset",
                nullable: false,
                defaultValue: new DateTimeOffset(new DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)));

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "ServerUpdatedAt",
                table: "book_fingerprints",
                type: "datetimeoffset",
                nullable: false,
                defaultValue: new DateTimeOffset(new DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)));

            migrationBuilder.CreateIndex(
                name: "IX_reading_sessions_ServerUpdatedAt",
                table: "reading_sessions",
                column: "ServerUpdatedAt");

            migrationBuilder.CreateIndex(
                name: "IX_reading_plans_ServerUpdatedAt",
                table: "reading_plans",
                column: "ServerUpdatedAt");

            migrationBuilder.CreateIndex(
                name: "IX_reading_log_ServerUpdatedAt",
                table: "reading_log",
                column: "ServerUpdatedAt");

            migrationBuilder.CreateIndex(
                name: "IX_books_UserId_ServerUpdatedAt",
                table: "books",
                columns: new[] { "UserId", "ServerUpdatedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_book_fingerprints_ServerUpdatedAt",
                table: "book_fingerprints",
                column: "ServerUpdatedAt");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_reading_sessions_ServerUpdatedAt",
                table: "reading_sessions");

            migrationBuilder.DropIndex(
                name: "IX_reading_plans_ServerUpdatedAt",
                table: "reading_plans");

            migrationBuilder.DropIndex(
                name: "IX_reading_log_ServerUpdatedAt",
                table: "reading_log");

            migrationBuilder.DropIndex(
                name: "IX_books_UserId_ServerUpdatedAt",
                table: "books");

            migrationBuilder.DropIndex(
                name: "IX_book_fingerprints_ServerUpdatedAt",
                table: "book_fingerprints");

            migrationBuilder.DropColumn(
                name: "ServerUpdatedAt",
                table: "reading_sessions");

            migrationBuilder.DropColumn(
                name: "ServerUpdatedAt",
                table: "reading_plans");

            migrationBuilder.DropColumn(
                name: "ServerUpdatedAt",
                table: "reading_log");

            migrationBuilder.DropColumn(
                name: "ServerUpdatedAt",
                table: "books");

            migrationBuilder.DropColumn(
                name: "ServerUpdatedAt",
                table: "book_fingerprints");

            migrationBuilder.CreateIndex(
                name: "IX_books_UserId_UpdatedAt",
                table: "books",
                columns: new[] { "UserId", "UpdatedAt" });
        }
    }
}
