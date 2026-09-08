using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ICanRead.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddSessionTombstone : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "DeletedAt",
                table: "reading_sessions",
                type: "datetimeoffset",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "DeletedAt",
                table: "reading_sessions");
        }
    }
}
