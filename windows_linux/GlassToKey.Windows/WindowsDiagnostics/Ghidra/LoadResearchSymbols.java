// Apply an already matched local public PDB to the analysis database only.
// @category GlassToKey
import ghidra.app.script.GhidraScript;
import ghidra.app.util.bin.format.pdb2.pdbreader.AbstractPdb;
import ghidra.app.util.bin.format.pdb2.pdbreader.PdbParser;
import ghidra.app.util.bin.format.pdb2.pdbreader.PdbReaderOptions;
import ghidra.app.util.importer.MessageLog;
import ghidra.app.util.pdb.pdbapplicator.DefaultPdbApplicator;
import ghidra.app.util.pdb.pdbapplicator.PdbApplicatorOptions;
import ghidra.program.model.symbol.Symbol;
import ghidra.program.model.symbol.SymbolIterator;
import java.io.File;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.util.regex.Pattern;

public class LoadResearchSymbols extends GhidraScript {
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if(args.length != 3) throw new IllegalArgumentException("PDB file, output directory, symbol regex required");
        MessageLog log = new MessageLog();
        try(AbstractPdb pdb = PdbParser.parse(new File(args[0]),new PdbReaderOptions(),monitor)) {
            pdb.deserialize();
            DefaultPdbApplicator app = new DefaultPdbApplicator(pdb,currentProgram,
                currentProgram.getDataTypeManager(),currentProgram.getImageBase(),
                new PdbApplicatorOptions(),monitor,log);
            app.applyNoAnalysisState();
        }
        Pattern pattern = Pattern.compile(args[2],Pattern.CASE_INSENSITIVE);
        File output = new File(args[1],currentProgram.getName()+".symbol-matches.txt");
        try(PrintWriter writer = new PrintWriter(output,StandardCharsets.UTF_8.name())) {
            writer.println("PDB " + args[0]);
            SymbolIterator symbols = currentProgram.getSymbolTable().getAllSymbols(true);
            while(symbols.hasNext()) {
                Symbol symbol = symbols.next();
                if(pattern.matcher(symbol.getName(true)).find())
                    writer.println(symbol.getAddress()+" "+symbol.getName(true));
            }
            writer.println("APPLICATOR_LOG\n"+log.toString());
        }
        println("Applied public symbols; matches exported to " + output);
    }
}
