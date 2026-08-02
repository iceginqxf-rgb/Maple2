using System.CommandLine;
using System.CommandLine.Invocation;
using System.CommandLine.IO;
using System.Numerics;
using Maple2.Model.Enum;
using Maple2.Model.Metadata;
using Maple2.Server.Game.Model;
using Maple2.Server.Game.Model.Skill;
using Maple2.Server.Game.Packets;
using Maple2.Server.Game.Session;

namespace Maple2.Server.Game.Commands;

public class DamageCommand : GameCommand {
    private readonly GameSession session;

    public DamageCommand(GameSession session) : base(AdminPermissions.GameMaster, "damage", "Deal damage to nearby NPCs/Mobs.") {
        this.session = session;

        var amount = new Argument<long>("amount", "Amount of damage to deal.");
        var distance = new Option<int>(["--distance", "-d"], () => 200, "Radius to damage mobs/npcs.");
        var all = new Option<bool>("--all", () => false, "Damage all mobs in map.");

        AddArgument(amount);
        AddOption(distance);
        AddOption(all);
        this.SetHandler<InvocationContext, long, int, bool>(Handle, amount, distance, all);
    }

    private void Handle(InvocationContext ctx, long amount, int distance, bool all) {
        if (session.Field is null) return;
        if (!session.SkillMetadata.TryGet(10000001, 1, out SkillMetadata? skill)) {
            ctx.Console.Out.WriteLine("Skill not found.");
            return;
        }

        int count = 0;
        IEnumerable<FieldNpc> targets;
        if (all) {
            targets = session.Field.Mobs.Values.Cast<FieldNpc>().Concat(session.Field.Npcs.Values);
        } else {
            targets = session.Field.Mobs.Values
                .Where(npc => Vector3.Distance(npc.Position, session.Player.Position) <= distance)
                .Cast<FieldNpc>()
                .Concat(session.Field.Npcs.Values
                    .Where(npc => Vector3.Distance(npc.Position, session.Player.Position) <= distance));
        }

        foreach (FieldNpc npc in targets) {
            if (npc.Stats is null) continue;
            long currentHp = npc.Stats.Values[BasicAttribute.Health].Current;
            if (currentHp <= 0) continue;

            long actualDamage = Math.Min(amount, currentHp);

            var damageRecord = new DamageRecord(skill, skill.Data.Motions[0].Attacks[0]) {
                CasterId = session.Player.ObjectId,
                TargetUid = ((long) Random.Shared.Next(int.MinValue, int.MaxValue) << 32) | (uint) Random.Shared.Next(int.MinValue, int.MaxValue),
                OwnerId = session.Player.ObjectId,
                SkillId = skill.Id,
                Level = skill.Level,
                AttackPoint = 0,
                MotionPoint = 0,
                Position = npc.Position,
                Direction = session.Player.Rotation,
            };
            var target = new DamageRecordTarget(npc) {
                Position = session.Player.Position,
                Direction = session.Player.Rotation,
            };
            target.AddDamage(DamageType.Normal, actualDamage);
            damageRecord.Targets.TryAdd(npc.ObjectId, target);
            npc.Stats.Values[BasicAttribute.Health].Add(-actualDamage);
            session.Field.Broadcast(StatsPacket.Update(npc, BasicAttribute.Health));
            session.Field.Broadcast(SkillDamagePacket.Damage(damageRecord));

            count++;
        }

        ctx.Console.Out.WriteLine($"Dealt {amount} damage to {count} NPC(s).");
    }
}
